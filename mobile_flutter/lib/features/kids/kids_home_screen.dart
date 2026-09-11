import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/biometrics/face_biometrics.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/ln_components.dart';
import '../discovery/discovery_screen.dart';
import '../feed/comments_sheet.dart';
import '../feed/report_options_sheet.dart';
import '../feed/share_sheet.dart';

/// LittleNet V2 – Home screen.
///
/// Visual language:
///  - Pure white background
///  - Top bar: LittleNet logotype left, message icon right
///  - Stories row immediately below top bar (no section header)
///  - Screen-time chip in app bar (restrained, small)
///  - Learning challenge card – minimal, not "dashboard-y"
///  - Suggested classmates horizontal scroll
///  - Recent community posts as clean feed tiles
class KidsHomeScreen extends StatefulWidget {
  const KidsHomeScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<KidsHomeScreen> createState() => _KidsHomeScreenState();
}

class _KidsHomeScreenState extends State<KidsHomeScreen> {
  bool _isLoading = true;
  String? _error;
  String? _gate;
  bool _quizCompletedLocally = false;

  Map<String, dynamic>? _profile;
  List<dynamic> _stories = [];
  List<dynamic> _posts = [];
  List<dynamic> _reels = [];
  List<dynamic> _suggested = [];
  int _minutesToday = 0;

  @override
  void initState() {
    super.initState();
    _fetchHomeData();
  }

  Future<void> _fetchHomeData() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _gate = null;
    });

    try {
      final res =
          await widget.authState.apiClient.get('/api/mobile/v1/kids/home');
      if (res['ok'] == true) {
        setState(() {
          _profile = res['profile'] as Map<String, dynamic>?;
          _stories = res['stories'] as List<dynamic>? ?? [];
          _posts = res['posts'] as List<dynamic>? ?? [];
          _reels = res['reels'] as List<dynamic>? ?? [];
          _suggested = res['suggested'] as List<dynamic>? ?? [];
          _minutesToday = res['minutes_today'] as int? ?? 0;
        });
      }
    } on ApiException catch (e) {
      setState(() {
        if (e.statusCode == 423) {
          _gate = e.payload?['gate']?.toString() ?? 'screen_time';
          _error = _gate == 'quiet_hours'
              ? 'LittleNet is resting for quiet hours 🌙'
              : 'Screen time limit reached for today ⏳';
        } else if (e.statusCode == 428) {
          _gate = e.payload?['gate']?.toString() ?? 'quiz';
          if (_gate == 'quiz' && _quizCompletedLocally) {
            _gate = null;
            _error = null;
          } else {
            _error = _gate == 'face'
                ? 'Facial security setup needed before entering Kids Mode.'
                : 'Complete your welcome quiz to unlock your feed!';
          }
        } else {
          _error = 'Unable to load home right now.';
        }
      });
    } catch (_) {
      setState(() => _error = 'Network connection lost.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isSettingUpFace = false;

  Future<void> _handleSetupChildFace() async {
    setState(() => _isSettingUpFace = true);
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 85,
      );
      if (photo == null) {
        setState(() => _isSettingUpFace = false);
        return;
      }

      final bytes = await photo.readAsBytes();
      final photoB64 = base64Encode(bytes);

      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/kids/face/enroll',
        body: {'photo_b64': photoB64},
      );

      if (res['ok'] == true) {
        final uid = widget.authState.currentUser?.userId;
        if (uid != null) {
          try {
            final inputImage = InputImage.fromFilePath(photo.path);
            final detector =
                FaceDetector(options: FaceDetectorOptions(enableLandmarks: true));
            final faces = await detector.processImage(inputImage);
            if (faces.isNotEmpty) {
              final neural =
                  await LocalFaceBiometrics.extractNeuralEmbedding(bytes, faces.first);
              await LocalFaceBiometrics.saveTemplate(uid, neural);
            }
            detector.close();
            if (res['biometric_key'] != null) {
              await LocalFaceBiometrics.saveBiometricKey(
                  uid, res['biometric_key'].toString());
            }
          } catch (_) {}
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Facial security setup complete! Unlocking Kids Mode...'),
              backgroundColor: AppColors.success,
            ),
          );
        }
        await _fetchHomeData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['error']?.toString() ?? 'Face setup failed.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Setup failed: ${e.message}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera or setup error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSettingUpFace = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(),
        body: RefreshIndicator(
          onRefresh: _fetchHomeData,
          color: AppColors.primary,
          child: _buildBody(),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    final displayName = _profile?['full_name'] as String? ??
        widget.authState.currentUser?.fullName ??
        'Friend';

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleSpacing: 16,
      title: Row(
        children: [
          // LittleNet wordmark / brand
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: 'Little',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF262626),
                    letterSpacing: -0.5,
                  ),
                ),
                TextSpan(
                  text: 'Net',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Greeting chip – subtle, not large
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Hi, ${displayName.split(' ').first}! 👋',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF8E8E8E)),
            ),
          ),
        ],
      ),
      actions: [
        // Screen-time indicator
        if (_minutesToday > 0)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 14),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 13, color: Color(0xFF8E8E8E)),
                const SizedBox(width: 3),
                Text('${_minutesToday}m',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8E8E8E),
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        // Notifications
        IconButton(
          icon: const Icon(Icons.favorite_border_rounded,
              color: Color(0xFF262626), size: 24),
          tooltip: 'Notifications',
          onPressed: () =>
              Navigator.of(context).pushNamed('/kids/notifications'),
        ),
        // Messages
        IconButton(
          icon: const Icon(Icons.send_rounded, color: Color(0xFF262626), size: 24),
          tooltip: 'Messages',
          onPressed: () => Navigator.of(context).pushNamed('/kids/messages'),
        ),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(0.5),
        child: Divider(height: 0.5, thickness: 0.5, color: Color(0xFFDBDBDB)),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading || _isSettingUpFace) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (_isSettingUpFace) ...[
              const SizedBox(height: 16),
              const Text('Enrolling facial security...',
                  style: TextStyle(color: Color(0xFF8E8E8E))),
            ],
          ],
        ),
      );
    }

    if (_error != null) {
      VoidCallback? action;
      String? actionLabel;
      String? subtitle;

      if (_gate == 'face') {
        action = _handleSetupChildFace;
        actionLabel = 'Set Up Face Security Now';
        subtitle =
            'A quick face photo is required to ensure safe, verified access to Kids Mode.';
      } else if (_gate == 'quiz') {
        action = () => Navigator.of(context)
            .pushNamed('/kids/quiz')
            .then((res) {
              if (res == true) {
                setState(() {
                  _quizCompletedLocally = true;
                  _gate = null;
                  _error = null;
                });
              }
              _fetchHomeData();
            });
        actionLabel = 'Take Safety Quiz';
        subtitle = 'Complete your quick welcome quiz to unlock your feed!';
      } else if (_gate == null) {
        action = _fetchHomeData;
        actionLabel = 'Try Again';
        subtitle = 'Pull down or tap to retry.';
      }

      return LnEmptyState(
        emoji: _gate == 'quiet_hours'
            ? '🌙'
            : _gate == 'screen_time'
                ? '⏳'
                : _gate == 'face'
                    ? '🛡️'
                    : '⚠️',
        title: _error!,
        subtitle: subtitle,
        action: action,
        actionLabel: actionLabel ?? 'Try Again',
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // ── Stories Row ──────────────────────────────
        SliverToBoxAdapter(
          child: _StoriesRow(
            stories: _stories,
            onSearch: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DiscoveryScreen(authState: widget.authState))),
          ),
        ),
        const SliverToBoxAdapter(
          child: Divider(height: 1, thickness: 0.4, color: Color(0xFFDBDBDB)),
        ),

        // ── Learning Challenge ────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).pushNamed('/kids/quiz'),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Text('🚀', style: TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Today's Challenge",
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF262626))),
                          SizedBox(height: 2),
                          Text('Answer 3 questions · Earn safe-points',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF8E8E8E))),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.primary, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Safe Reels Row ────────────────────────────
        if (_reels.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 18)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Safe Short Videos',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF262626))),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pushNamed('/kids/reels'),
                    child: const Text('See all',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.primary,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 172,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _reels.length,
                itemBuilder: (ctx, i) => _ReelThumbnail(reel: _reels[i]),
              ),
            ),
          ),
        ],

        // ── Suggested Classmates ──────────────────────
        if (_suggested.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 18)),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Classmates you might know',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF262626))),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _suggested.length,
                itemBuilder: (ctx, i) =>
                    _SuggestedCard(classmate: _suggested[i]),
              ),
            ),
          ),
        ],

        // ── Divider before posts ──────────────────────
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, thickness: 0.4, color: Color(0xFFDBDBDB)),
          ),
        ),

        // ── Community posts ───────────────────────────
        if (_posts.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: LnEmptyState(
              emoji: '🌱',
              title: 'No posts yet today',
              subtitle: 'Check the Feed tab for curated learning stories!',
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final item = _posts[i] as Map<String, dynamic>;
                final postId = item['post_id'] as int?;
                return LnPostCard(
                  item: item,
                  onComment: postId != null
                      ? () => CommentsSheet.show(
                            context,
                            authState: widget.authState,
                            postId: postId,
                            postCaption: item['caption']?.toString(),
                          )
                      : null,
                  onShare: () => ShareSheet.show(
                    context,
                    authState: widget.authState,
                    postId: postId,
                    postTitle: item['caption']?.toString(),
                  ),
                  onMore: () => ReportOptionsSheet.show(
                    context,
                    authState: widget.authState,
                    postId: postId,
                    authorHandle: item['username'] != null ? '@${item['username']}' : '@classmate',
                  ),
                );
              },
              childCount: _posts.length,
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Stories row (horizontal scroll with gradient rings)
// ─────────────────────────────────────────────────────────────────
class _StoriesRow extends StatelessWidget {
  const _StoriesRow({required this.stories, this.onSearch});

  final List<dynamic> stories;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: (stories.isEmpty ? 0 : stories.length) + 1,
        itemBuilder: (ctx, i) {
          // First item – "Your Story" / search bubble
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(right: 14),
              child: GestureDetector(
                onTap: onSearch,
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFF5F5F5),
                            border: Border.all(
                                color: const Color(0xFFDBDBDB), width: 1),
                          ),
                          child: const Icon(Icons.search_rounded,
                              color: Color(0xFF8E8E8E), size: 26),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    const Text('Discover',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF8E8E8E))),
                  ],
                ),
              ),
            );
          }

          final s = stories[i - 1] as Map<String, dynamic>;
          final name = s['full_name']?.toString() ?? 'Student';
          final avatarUrl = s['avatar_url']?.toString();
          final seen = s['seen'] == true;

          return Padding(
            padding: const EdgeInsets.only(right: 14),
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pushNamed(
                  '/kids/story-viewer',
                  arguments: {
                    'author_name': name,
                    'author_handle': s['username'] != null ? '@${s['username']}' : '@classmate',
                    'avatar_url': avatarUrl,
                    'media_url': s['media_url'],
                    'caption': s['caption'] ?? 'Classroom STEM update! 🚀',
                    'story_music': s['story_music'],
                  },
                );
              },
              child: Column(
                children: [
                  LnStoryRing(
                    seen: seen,
                    size: 56,
                    child: LnAvatar(
                      url: avatarUrl,
                      name: name,
                      radius: 26,
                    ),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    width: 60,
                    child: Text(
                      name.split(' ').first,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF262626)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Reel thumbnail tile
// ─────────────────────────────────────────────────────────────────
class _ReelThumbnail extends StatelessWidget {
  const _ReelThumbnail({required this.reel});

  final dynamic reel;

  @override
  Widget build(BuildContext context) {
    final r = reel as Map<String, dynamic>;
    final posterUrl = r['poster_url']?.toString();
    final caption = r['caption']?.toString() ?? 'Learning Reel';

    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed('/kids/reels'),
      child: Container(
        width: 108,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(10),
          image: posterUrl != null
              ? DecorationImage(
                  image: NetworkImage(posterUrl), fit: BoxFit.cover)
              : null,
        ),
        child: Stack(
          children: [
            // Dark scrim at bottom
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.5, 1.0],
                    colors: [Colors.transparent, Color(0xCC000000)],
                  ),
                ),
              ),
            ),
            // Play icon
            const Center(
              child: Icon(Icons.play_circle_fill,
                  color: Colors.white, size: 32),
            ),
            // Caption
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Text(
                caption,
                style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Suggested classmate card
// ─────────────────────────────────────────────────────────────────
class _SuggestedCard extends StatelessWidget {
  const _SuggestedCard({required this.classmate});

  final dynamic classmate;

  @override
  Widget build(BuildContext context) {
    final c = classmate as Map<String, dynamic>;
    final name = c['full_name']?.toString() ?? 'Classmate';
    final avatarUrl = c['avatar_url']?.toString();

    return Container(
      width: 108,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEBEBEB)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LnAvatar(url: avatarUrl, name: name, radius: 22),
          const SizedBox(height: 6),
          Text(
            name.split(' ').first,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF262626)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Follow',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

