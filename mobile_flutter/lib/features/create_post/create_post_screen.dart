import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/gradient_scaffold.dart';

enum PostKind { post, reel, story }

enum PostModerationOutcome {
  none,
  allowed,
  review,
  blocked,
  error,
}

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

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _picker = ImagePicker();
  final _captionController = TextEditingController();

  late PostKind _kind;
  String _selectedCategory = 'Art';
  String _audience = 'ALL';

  File? _selectedFile;
  bool _isVideo = false;
  VideoPlayerController? _videoController;

  bool _isUploading = false;
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

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
  }

  @override
  void dispose() {
    _captionController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
      if (picked != null) {
        _setFile(File(picked.path), isVideo: false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to access photo: $e')),
      );
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
      if (picked != null) {
        _setFile(File(picked.path), isVideo: true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to access video: $e')),
      );
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
      final controller = VideoPlayerController.file(file);
      _videoController = controller;
      controller.initialize().then((_) {
        if (mounted) {
          controller.setVolume(0.0);
          controller.setLooping(true);
          controller.play();
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

  Future<void> _submitPost() async {
    final caption = _captionController.text.trim();
    if (_selectedFile == null && caption.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select an image/video or write a caption')),
      );
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

    setState(() {
      _isUploading = true;
      _outcome = PostModerationOutcome.none;
      _statusMessage = null;
      _rejectionReason = null;
    });

    try {
      final kindStr = _kind == PostKind.reel
          ? 'reel'
          : _kind == PostKind.story
              ? 'story'
              : 'post';

      final res = await widget.authState.apiClient.multipart(
        '/api/mobile/v1/kids/posts',
        file: _selectedFile,
        fileField: 'media',
        fields: {
          'caption': caption,
          'content_category': _selectedCategory,
          'audience_age_group': _audience,
          'kind': kindStr,
        },
      );

      final status = (res['status'] as String? ?? '').toUpperCase();
      if (res['ok'] == true && status == 'ALLOW') {
        setState(() {
          _outcome = PostModerationOutcome.allowed;
          _statusMessage = 'Your post passed safety checks and is published!';
        });
      } else if (res['ok'] == true && status == 'REVIEW') {
        setState(() {
          _outcome = PostModerationOutcome.review;
          _statusMessage =
              'Sent to Parent Safety Review. Your parent will review it before it appears publicly.';
        });
      } else {
        setState(() {
          _outcome = PostModerationOutcome.error;
          _statusMessage = 'Post could not be published at this time.';
        });
      }
    } on ApiException catch (e) {
      if (e.payload?['blocked'] == true || e.message.contains('blocked')) {
        setState(() {
          _outcome = PostModerationOutcome.blocked;
          _rejectionReason = e.payload?['reason'] as String? ??
              'Content could not be shared because it does not follow child safety standards.';
          _statusMessage =
              'Content cannot be shared under LittleNet safety rules.';
        });
      } else {
        setState(() {
          _outcome = PostModerationOutcome.error;
          _statusMessage = 'Failed: ${e.message}';
        });
      }
    } catch (_) {
      setState(() {
        _outcome = PostModerationOutcome.error;
        _statusMessage =
            'Unable to connect to safety server. Post held safely.';
      });
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: Text(
          _kind == PostKind.reel
              ? 'Create Reel 🎬'
              : _kind == PostKind.story
                  ? 'Add Story 📖'
                  : 'New Post ✨',
        ),
        actions: [
          if (_selectedFile != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear media',
              onPressed: _clearSelection,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kind Selector Tabs
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  _kindTab('Post', PostKind.post),
                  _kindTab('Reel', PostKind.reel),
                  _kindTab('Story', PostKind.story),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Media Preview or Picker Actions
            if (_selectedFile == null) ...[
              Container(
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: AppColors.kidsAccent.withValues(alpha: 0.3),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_photo_alternate_outlined,
                        size: 48, color: AppColors.kidsAccent),
                    const SizedBox(height: AppSpacing.sm),
                    const Text('Share what you learned or created',
                        style: AppTypography.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'AI Safe Moderation active · No audio uploads',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textMutedDark),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Camera'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        ElevatedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Photos'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.1),
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        ElevatedButton.icon(
                          onPressed: () => _pickVideo(ImageSource.gallery),
                          icon: const Icon(Icons.videocam_outlined),
                          label: const Text('Video'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.1),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Media Preview
              Container(
                height: 260,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.kidsAccent),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isVideo) ...[
                      if (_videoController != null &&
                          _videoController!.value.isInitialized)
                        AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        )
                      else
                        const CircularProgressIndicator(),
                    ] else ...[
                      Image.file(
                        _selectedFile!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                      ),
                    ],
                    Positioned(
                      top: 8,
                      right: 8,
                      child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: _clearSelection,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),

            // Category & Caption
            AppTextField(
              label: 'Caption / Story',
              hint: 'Write about your project, idea, or discovery...',
              controller: _captionController,
              maxLines: 3,
              prefixIcon: Icons.edit_note_rounded,
            ),
            const SizedBox(height: AppSpacing.md),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      prefixIcon: const Icon(Icons.category_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    items: _categories.map((c) {
                      return DropdownMenuItem(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCategory = val);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _audience,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Audience',
                      prefixIcon: const Icon(Icons.groups_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'ALL',
                          child: Text('All Kids',
                              overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(
                          value: '6-8',
                          child: Text('Ages 6-8',
                              overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(
                          value: '9-11',
                          child: Text('Ages 9-11',
                              overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(
                          value: '12-13',
                          child: Text('Ages 12-13',
                              overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(
                          value: '14-18',
                          child: Text('Ages 14-18',
                              overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _audience = val);
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),

            // Moderation Outcome Feedback
            if (_outcome != PostModerationOutcome.none) ...[
              _buildOutcomeBanner(),
              const SizedBox(height: AppSpacing.md),
            ],

            // Submit Button
            AppButton(
              text: _kind == PostKind.reel
                  ? 'Share Reel'
                  : _kind == PostKind.story
                      ? 'Share Story'
                      : 'Publish Post',
              icon: Icons.send_rounded,
              isLoading: _isUploading,
              onPressed: _isUploading ? null : _submitPost,
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindTab(String title, PostKind kind) {
    final isSelected = _kind == kind;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _kind = kind;
            _clearSelection();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.kidsAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Center(
            child: Text(
              title,
              style: AppTypography.labelLarge.copyWith(
                color: isSelected ? Colors.black : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutcomeBanner() {
    Color bg;
    Color border;
    IconData icon;
    String title;

    switch (_outcome) {
      case PostModerationOutcome.allowed:
        bg = AppColors.success.withValues(alpha: 0.15);
        border = AppColors.success;
        icon = Icons.check_circle_outline;
        title = 'Published!';
      case PostModerationOutcome.review:
        bg = Colors.amber.withValues(alpha: 0.15);
        border = Colors.amber;
        icon = Icons.pending_outlined;
        title = 'Parent Review Required';
      case PostModerationOutcome.blocked:
        bg = AppColors.error.withValues(alpha: 0.15);
        border = AppColors.error;
        icon = Icons.gpp_bad_outlined;
        title = 'Blocked for Safety';
      case PostModerationOutcome.error:
      case PostModerationOutcome.none:
        bg = Colors.grey.withValues(alpha: 0.15);
        border = Colors.grey;
        icon = Icons.info_outline;
        title = 'Notice';
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: border),
              const SizedBox(width: AppSpacing.sm),
              Text(title,
                  style: AppTypography.titleMedium.copyWith(color: border)),
            ],
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 4),
            Text(_statusMessage!, style: AppTypography.bodyMedium),
          ],
          if (_rejectionReason != null) ...[
            const SizedBox(height: 4),
            Text(
              'Reason: $_rejectionReason',
              style: AppTypography.caption
                  .copyWith(color: AppColors.textMutedDark),
            ),
          ],
        ],
      ),
    );
  }
}
