import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/widgets/ln_components.dart';
import '../../core/upload/upload_manager.dart';
import 'reel_controller_pool.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  final ReelControllerPool _pool = ReelControllerPool();
  final Set<String> _recordedImpressions = {};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  String? _gate;

  String? _sessionId;
  int _cursor = 0;
  bool _hasMore = true;
  List<Map<String, dynamic>> _reels = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pool.onStateChanged = () {
      if (mounted) setState(() {});
    };
    _pool.onRefreshUrl = (index, reel) async {
      final postId = reel['post_id'];
      if (postId == null) return null;
      try {
        final res = await widget.authState.apiClient.get('/api/mobile/v1/media/$postId/url');
        if (res['ok'] == true && res['media_url'] != null) {
          return res['media_url'] as String;
        }
      } catch (_) {}
      return null;
    };
    UploadManager.instance.addListener(_onUploadChanged);
    _loadInitialReels();
  }

  void _onUploadChanged() {
    if (UploadManager.instance.state.stage == UploadStage.allowed && mounted) {
      _loadInitialReels();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _pool.onAppLifecycleChanged(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UploadManager.instance.removeListener(_onUploadChanged);
    _pageController.dispose();
    _pool.disposeAll();
    super.dispose();
  }

  Future<void> _loadInitialReels() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _gate = null;
      _cursor = 0;
      _reels = [];
    });
    _pool.disposeAll();

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v2/kids/reels',
        query: {'cursor': '0', 'limit': '6'},
      );

      if (res['ok'] == true) {
        final items = (res['items'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        setState(() {
          _sessionId = res['session_id']?.toString();
          _cursor = res['next_cursor'] as int? ?? items.length;
          _hasMore = res['has_more'] as bool? ?? false;
          _reels = items;
        });

        if (items.isNotEmpty) {
          if (!mounted) return;
          _pool.onPageChanged(0, items, context);
          _recordImpression(0);
        }
      }
    } on ApiException catch (e) {
      setState(() {
        if (e.statusCode == 403) {
          _gate = 'disabled_by_parent';
          _error = 'Reels are currently turned off by your parent.';
        } else if (e.statusCode == 423) {
          _gate = 'screen_time';
          _error = 'Screen time limit reached for today! ⏳';
        } else {
          _error = e.message;
        }
      });
    } catch (_) {
      setState(() => _error = 'Unable to connect to Reels. Check your Wi-Fi.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v2/kids/reels',
        query: {
          'cursor': '$_cursor',
          'limit': '6',
          if (_sessionId != null) 'session_id': _sessionId!,
        },
      );

      if (res['ok'] == true) {
        final newItems = (res['items'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        setState(() {
          _cursor = res['next_cursor'] as int? ?? (_cursor + newItems.length);
          _hasMore = res['has_more'] as bool? ?? false;
          _reels.addAll(newItems);
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _onPageChanged(int index) {
    setState(() {});
    _pool.onPageChanged(index, _reels, context);
    _recordImpression(index);

    if (index >= _reels.length - 2 && _hasMore && !_isLoadingMore) {
      _loadNextPage();
    }
  }

  void _recordImpression(int index) {
    if (index < 0 || index >= _reels.length || _sessionId == null) return;
    final item = _reels[index];
    final key = '${item['source_type']}_${item['source_id']}';

    if (!_recordedImpressions.contains(key)) {
      _recordedImpressions.add(key);
      widget.authState.apiClient.post(
        '/api/mobile/v2/kids/impressions',
        body: {
          'session_id': _sessionId,
          'source_type': item['source_type'],
          'source_id': item['source_id'],
          'surface': 'REELS',
        },
      ).catchError((_) => <String, dynamic>{});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_error != null) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            title: const Text(
              'Reels',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF262626),
              ),
            ),
          ),
          body: LnEmptyState(
            emoji: _gate == 'disabled_by_parent' ? '🔒' : '⏳',
            title: _gate == 'disabled_by_parent'
                ? 'Reels turned off'
                : 'Screen time reached',
            subtitle: _error,
            action: _gate == null ? _loadInitialReels : null,
            actionLabel: 'Retry',
          ),
        ),
      );
    }

    if (_reels.isEmpty) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            title: const Text('Reels',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF262626))),
          ),
          body: LnEmptyState(
            emoji: '🎬',
            title: 'No reels right now',
            subtitle: 'Check back soon for safe educational videos!',
            action: _loadInitialReels,
            actionLabel: 'Refresh',
          ),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: _reels.length,
          onPageChanged: _onPageChanged,
          itemBuilder: (context, index) {
            final reel = _reels[index];
            final controller = _pool.getController(index);
            final isInitialized = _pool.isReady(index);
            final authorName = reel['full_name']?.toString() ??
                reel['author_name']?.toString() ?? 'LittleNet';
            final avatarUrl = reel['avatar_url']?.toString();
            final caption = reel['caption']?.toString() ??
                reel['title']?.toString() ?? '';
            final category = reel['category']?.toString() ??
                reel['content_category']?.toString() ?? 'Learning';
            final isCurated = reel['source_type'] == 'CURATED';
            final likeCount = reel['likes'] as int? ?? reel['like_count'] as int? ?? 0;
            final posterUrl = reel['poster_url']?.toString();

            return Stack(
              fit: StackFit.expand,
              children: [
                // ── Layer 1: Poster / Immediate placeholder ──
                if (posterUrl != null && posterUrl.isNotEmpty)
                  Positioned.fill(
                    child: Image.network(
                      posterUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Color(0xFF1A1A2E),
                        child: Center(
                          child: Icon(Icons.movie_creation_outlined,
                              size: 64, color: Colors.white24),
                        ),
                      ),
                    ),
                  )
                else
                  Positioned.fill(
                    child: ColoredBox(
                      color: const Color(0xFF1A1A2E),
                      child: Center(
                        child: isInitialized
                            ? const SizedBox.shrink()
                            : const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white38,
                                ),
                              ),
                      ),
                    ),
                  ),

                // ── Layer 2: Video Player (seamless overlay) ────
                if (isInitialized && controller != null)
                  Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  ),

                // ── Full bottom gradient scrim ────────────
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.4, 1.0],
                        colors: [Colors.transparent, Color(0xCC000000)],
                      ),
                    ),
                  ),
                ),

                // ── Bottom-left: author + caption ─────────
                Positioned(
                  bottom: 32,
                  left: 16,
                  right: 72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Author row
                      Row(
                        children: [
                          LnAvatar(
                              url: avatarUrl, name: authorName, radius: 14),
                          const SizedBox(width: 8),
                          Text(
                            authorName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700),
                          ),
                          if (isCurated) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00B894),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Safe Pick',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Category pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          category,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Caption
                      if (caption.isNotEmpty)
                        Text(
                          caption,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.4),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),

                // ── Right action column ───────────────────
                Positioned(
                  bottom: 40,
                  right: 10,
                  child: Column(
                    children: [
                      // Like
                      Column(
                        children: [
                          IconButton(
                            icon: Icon(
                              reel['viewer_liked'] == true
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: reel['viewer_liked'] == true
                                  ? const Color(0xFFED4956)
                                  : Colors.white,
                              size: 30,
                            ),
                            onPressed: () {
                              setState(() {
                                reel['viewer_liked'] =
                                    !(reel['viewer_liked'] == true);
                              });
                            },
                          ),
                          if (likeCount > 0)
                            Text(
                              likeCount > 999
                                  ? '${(likeCount / 1000).toStringAsFixed(1)}k'
                                  : '$likeCount',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Share
                      const Column(
                        children: [
                          Icon(Icons.send_rounded,
                              color: Colors.white, size: 26),
                          SizedBox(height: 3),
                          Text('Share',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Top-right: index indicator ────────────
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${index + 1} / ${_reels.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
