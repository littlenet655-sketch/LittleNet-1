import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/ln_components.dart';
import 'comments_sheet.dart';

/// LittleNet V2 – Feed / Discover screen.
///
/// Clean Instagram-ish vertical feed:
/// - White background, thin top divider
/// - Each item → LnPostCard (full-width, 1:1 media)
/// - Curated items shown with a small "Safe Pick" badge
/// - Infinite scroll with auto-pagination
/// - Category filter chips pinned below app bar
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final ScrollController _scrollController = ScrollController();
  final Set<String> _recordedImpressions = {};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;

  String? _sessionId;
  int _cursor = 0;
  bool _hasMore = true;
  List<Map<String, dynamic>> _items = [];

  // Category filter
  final List<String> _categories = [
    'All',
    'Science',
    'Math',
    'Art',
    'Stories',
    'Nature',
  ];
  int _selectedCategory = 0;

  @override
  void initState() {
    super.initState();
    _loadInitialFeed();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      if (!_isLoadingMore && _hasMore) {
        _loadNextPage();
      }
    }
  }

  Future<void> _loadInitialFeed() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _cursor = 0;
      _items = [];
      _recordedImpressions.clear();
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v2/kids/feed',
        query: {'cursor': '0', 'limit': '10'},
      );

      if (res['ok'] == true) {
        final newItems = (res['items'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        setState(() {
          _sessionId = res['session_id']?.toString();
          _cursor = res['next_cursor'] as int? ?? newItems.length;
          _hasMore = res['has_more'] as bool? ?? false;
          _items = newItems;
        });

        _recordVisibleImpressions(newItems);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to connect. Check your internet.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v2/kids/feed',
        query: {
          'cursor': '$_cursor',
          'limit': '10',
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
          _items.addAll(newItems);
        });

        _recordVisibleImpressions(newItems);
      }
    } catch (_) {
      // Silent - allow retry on scroll
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _recordVisibleImpressions(List<Map<String, dynamic>> items) {
    if (_sessionId == null) return;
    for (final item in items) {
      final key = '${item['source_type']}_${item['source_id']}';
      if (!_recordedImpressions.contains(key)) {
        _recordedImpressions.add(key);
        widget.authState.apiClient.post(
          '/api/mobile/v2/kids/impressions',
          body: {
            'session_id': _sessionId,
            'source_type': item['source_type'],
            'source_id': item['source_id'],
            'surface': 'FEED',
          },
        ).catchError((_) => <String, dynamic>{});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: NestedScrollView(
          controller: _scrollController,
          headerSliverBuilder: (ctx, _) => [
            // ── App Bar ─────────────────────────────────
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 0,
              title: const Text(
                'Discover & Learn',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF262626),
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.tune_rounded,
                      color: Color(0xFF262626), size: 22),
                  onPressed: () {},
                  tooltip: 'Filter',
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(49),
                child: Column(
                  children: [
                    const Divider(
                        height: 1, thickness: 0.5, color: Color(0xFFDBDBDB)),
                    // Category filter chips
                    SizedBox(
                      height: 48,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: _categories.length,
                        itemBuilder: (ctx, i) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedCategory = i);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: _selectedCategory == i
                                    ? const Color(0xFF262626)
                                    : const Color(0xFFF0F0F0),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _categories[i],
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _selectedCategory == i
                                      ? Colors.white
                                      : const Color(0xFF262626),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          body: RefreshIndicator(
            onRefresh: _loadInitialFeed,
            color: AppColors.primary,
            child: _buildFeedBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildFeedBody() {
    if (_isLoading) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [1, 2, 3]
            .map((_) => const _FeedPostSkeleton())
            .toList(),
      );
    }

    if (_error != null && _items.isEmpty) {
      return LnEmptyState(
        emoji: '📡',
        title: 'Feed unavailable',
        subtitle: _error,
        action: _loadInitialFeed,
        actionLabel: 'Reload Feed',
      );
    }

    if (_items.isEmpty) {
      return LnEmptyState(
        emoji: '🌱',
        title: 'Your feed is empty right now',
        subtitle: 'Pull down to refresh or check back later!',
        action: _loadInitialFeed,
        actionLabel: 'Refresh',
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            ),
          );
        }

        final item = _items[index];
        final isCurated = item['source_type'] == 'CURATED';
        final postId = item['post_id'] as int?;

        // Decorate item with curated source display info
        final displayItem = Map<String, dynamic>.from(item);
        if (isCurated) {
          displayItem['full_name'] =
              item['title'] ?? item['full_name'] ?? 'LittleNet Pick';
          displayItem['content_category'] = '✅ Safe Pick · ${item['category'] ?? item['content_category'] ?? 'Educational'}';
        }

        return LnPostCard(
          item: displayItem,
          onLike: postId != null ? () => _toggleLike(item) : null,
          onComment: postId != null
              ? () => CommentsSheet.show(
                    context,
                    authState: widget.authState,
                    postId: postId,
                    postCaption: item['caption']?.toString(),
                  )
              : null,
          onShare: () {},
        );
      },
    );
  }

  Future<void> _toggleLike(Map<String, dynamic> item) async {
    final postId = item['post_id'] as int?;
    if (postId == null) return;
    final wasLiked = item['viewer_liked'] == true;
    setState(() => item['viewer_liked'] = !wasLiked);
    try {
      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/kids/posts/$postId/like',
      );
      if (mounted) setState(() => item['viewer_liked'] = res['liked'] == true);
    } catch (_) {
      if (mounted) setState(() => item['viewer_liked'] = wasLiked);
    }
  }
}

// ─────────────────────────────────────────────────────────────────
//  Post skeleton for loading state
// ─────────────────────────────────────────────────────────────────
class _FeedPostSkeleton extends StatelessWidget {
  const _FeedPostSkeleton();

  Widget _box(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: const Color(0xFFEEEEEE),
          borderRadius: BorderRadius.circular(4),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const CircleAvatar(
                  radius: 18, backgroundColor: Color(0xFFEEEEEE)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _box(130, 13),
                const SizedBox(height: 5),
                _box(90, 10),
              ]),
            ],
          ),
        ),
        AspectRatio(aspectRatio: 1, child: Container(color: const Color(0xFFEEEEEE))),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: _box(80, 12),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _box(double.infinity, 12),
        ),
        const SizedBox(height: 16),
        const Divider(height: 1, thickness: 0.4, color: Color(0xFFDBDBDB)),
      ],
    );
  }
}
