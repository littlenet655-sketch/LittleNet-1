import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_button.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final PageController _pageController = PageController();
  final Map<int, VideoPlayerController> _controllers = {};
  final Set<String> _recordedImpressions = {};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  String? _gate;

  String? _sessionId;
  int _cursor = 0;
  bool _hasMore = true;
  List<Map<String, dynamic>> _reels = [];
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadInitialReels();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _disposeAllControllers();
    super.dispose();
  }

  void _disposeAllControllers() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }

  Future<void> _loadInitialReels() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _gate = null;
      _cursor = 0;
      _reels = [];
      _disposeAllControllers();
    });

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
          _initControllerForIndex(0);
          if (items.length > 1) {
            _initControllerForIndex(1); // Preload next
          }
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
    setState(() => _focusedIndex = index);

    // 1. Play current, pause previous
    _controllers[index]?.play();
    _controllers[index - 1]?.pause();
    _controllers[index + 1]?.pause();

    // 2. Preload adjacent window: index - 1, index, index + 1
    _initControllerForIndex(index - 1);
    _initControllerForIndex(index);
    _initControllerForIndex(index + 1);

    // 3. Dispose distant controllers outside [index - 1, index + 1]
    final keysToRemove =
        _controllers.keys.where((k) => k < index - 1 || k > index + 1).toList();
    for (final k in keysToRemove) {
      _controllers[k]?.dispose();
      _controllers.remove(k);
    }

    // 4. Record impression
    _recordImpression(index);

    // 5. Pre-fetch next page if near end
    if (index >= _reels.length - 2 && _hasMore && !_isLoadingMore) {
      _loadNextPage();
    }
  }

  void _initControllerForIndex(int index) {
    if (index < 0 || index >= _reels.length) return;
    if (_controllers.containsKey(index)) return;

    final mediaUrl = _reels[index]['media_url']?.toString();
    if (mediaUrl == null || mediaUrl.isEmpty) return;

    final uri = Uri.parse(mediaUrl);
    late final VideoPlayerController controller;
    controller = VideoPlayerController.networkUrl(uri)
      ..setLooping(true)
      ..setVolume(0.0) // Kept muted consistent with retired audio scope
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          if (index == _focusedIndex) {
            controller.play();
          }
        }
      }).catchError((_) {
        // Video initialize failure handled gracefully by UI poster fallback
      });

    _controllers[index] = controller;
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
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Reels')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _gate == 'disabled_by_parent'
                      ? Icons.lock_outline_rounded
                      : Icons.hourglass_bottom_rounded,
                  size: 64,
                  color: AppColors.primary,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(_error!,
                    style: AppTypography.titleMedium,
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.lg),
                if (_gate == null)
                  AppButton(
                      text: 'Retry', onPressed: _loadInitialReels, width: 140),
              ],
            ),
          ),
        ),
      );
    }

    if (_reels.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Reels')),
        body: const Center(
          child: Text('No reels available right now. Check back soon! 🎬'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _reels.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) {
          final reel = _reels[index];
          final controller = _controllers[index];
          final isInitialized = controller?.value.isInitialized ?? false;

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Video Player or Poster Fallback
              if (isInitialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: controller!.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                )
              else if (reel['poster_url'] != null)
                Image.network(
                  reel['poster_url'].toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.movie_creation_outlined,
                        size: 64, color: Colors.white38),
                  ),
                )
              else
                const Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                ),

              // 2. Overlay Details (Caption, Category, Verified badge)
              Positioned(
                bottom: 32,
                left: 16,
                right: 72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            reel['category'] ??
                                reel['content_category'] ??
                                'Learning',
                            style: AppTypography.caption.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (reel['source_type'] == 'CURATED')
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.kidsMint,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: const Text('Safe Reel',
                                style: AppTypography.caption),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      reel['caption']?.toString() ??
                          reel['title']?.toString() ??
                          '',
                      style: AppTypography.bodyLarge.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w600),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // 3. Right Action Column (Like / Mute Indicator)
              Positioned(
                bottom: 40,
                right: 16,
                child: Column(
                  children: [
                    IconButton(
                      icon: Icon(
                        reel['viewer_liked'] == true
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: reel['viewer_liked'] == true
                            ? AppColors.error
                            : Colors.white,
                        size: 32,
                      ),
                      onPressed: () {
                        setState(() {
                          reel['viewer_liked'] =
                              !(reel['viewer_liked'] == true);
                        });
                      },
                    ),
                    const Text('Helpful',
                        style: TextStyle(color: Colors.white, fontSize: 11)),
                    const SizedBox(height: 16),
                    IconButton(
                      icon: const Icon(Icons.volume_off_rounded,
                          color: Colors.white70, size: 28),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Audio is retired for child-safe calm browsing.')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
