import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_button.dart';

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
          _cursor = res['next_cursor'] as int? ?? (newItems.length);
          _hasMore = res['has_more'] as bool? ?? false;
          _items = newItems;
        });

        // Record impressions for initial view
        _recordVisibleImpressions(newItems);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() =>
          _error = 'Unable to connect to LittleNet Feed. Check your internet.');
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
      // Background pagination failure, allow manual scroll retry
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
        // Fire-and-forget impression to server
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title:
            const Text('Discover & Learn 📚', style: AppTypography.titleMedium),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadInitialFeed,
        child: _buildFeedBody(),
      ),
    );
  }

  Widget _buildFeedBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 56, color: AppColors.textMuted),
              const SizedBox(height: AppSpacing.md),
              Text(_error!,
                  style: AppTypography.titleMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                  text: 'Reload Feed', onPressed: _loadInitialFeed, width: 160),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'Your feed is currently fresh and clean! Check back soon for more educational stories. 🌱',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final item = _items[index];
        final isCurated = item['source_type'] == 'CURATED';

        return Card(
          margin: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card Top Header
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: isCurated
                          ? AppColors.kidsGold.withValues(alpha: 0.2)
                          : AppColors.primaryLight,
                      child: Icon(
                        isCurated ? Icons.school_rounded : Icons.person_rounded,
                        color:
                            isCurated ? Colors.deepOrange : AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item['title'] ??
                                      item['full_name'] ??
                                      'Learning Story',
                                  style: AppTypography.labelLarge,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isCurated) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.kidsMint
                                        .withValues(alpha: 0.15),
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.sm),
                                  ),
                                  child: const Text('Verified Safe',
                                      style: AppTypography.caption),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            item['category'] ??
                                item['content_category'] ??
                                'Educational',
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Card Media (Image or Video Poster)
              if (item['media_url'] != null || item['poster_url'] != null) ...[
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    color: Colors.black12,
                    child: Image.network(
                      (item['poster_url'] ?? item['media_url']).toString(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_rounded,
                            size: 48, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              ],

              // Card Caption / Summary
              if (item['caption'] != null &&
                  item['caption'].toString().isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    item['caption'].toString(),
                    style: AppTypography.bodyLarge,
                  ),
                ),
              ],

              // Card Action Row (Like / Save)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        item['viewer_liked'] == true
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: item['viewer_liked'] == true
                            ? AppColors.error
                            : AppColors.textSecondary,
                      ),
                      onPressed: () {
                        setState(() {
                          item['viewer_liked'] =
                              !(item['viewer_liked'] == true);
                        });
                      },
                    ),
                    const Text('Helpful', style: AppTypography.caption),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.bookmark_border_rounded,
                          color: AppColors.textSecondary),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
