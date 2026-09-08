import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_button.dart';

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
          // Screen time or quiet hours
          _gate = e.payload?['gate']?.toString() ?? 'screen_time';
          _error = _gate == 'quiet_hours'
              ? 'LittleNet is resting for quiet hours. Time for bed! 🌙'
              : 'Screen time limit reached for today. See you tomorrow! ⏳';
        } else if (e.statusCode == 428) {
          // Onboarding quiz or face enrollment required
          _gate = e.payload?['gate']?.toString() ?? 'quiz';
          _error = _gate == 'face'
              ? 'Facial security setup needed before entering Kids Mode.'
              : 'Complete your quick welcome quiz to unlock your feed!';
        } else {
          _error = 'Unable to load your home right now. Please try again.';
        }
      });
    } catch (_) {
      setState(() => _error = 'Network connection lost. Please check Wi-Fi.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.star_rounded,
                  color: AppColors.kidsGold, size: 24),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Hello, ${_profile?['full_name'] ?? widget.authState.currentUser?.fullName ?? 'Friend'}! 🌟',
              style: AppTypography.titleMedium,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline_rounded,
                color: AppColors.textPrimary),
            tooltip: 'Messages',
            onPressed: () {
              Navigator.of(context).pushNamed('/kids/messages');
            },
          ),
          // Screen time pill indicator
          Container(
            margin: const EdgeInsets.only(right: AppSpacing.md),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                Text('$_minutesToday min',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchHomeData,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
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
              Icon(
                _gate == 'quiet_hours'
                    ? Icons.bedtime_rounded
                    : (_gate == 'screen_time'
                        ? Icons.hourglass_bottom_rounded
                        : Icons.info_outline),
                size: 64,
                color: _gate != null ? AppColors.primary : AppColors.error,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: AppTypography.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_gate == null)
                AppButton(
                  text: 'Try Again',
                  onPressed: _fetchHomeData,
                  width: 160,
                ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      children: [
        // 1. Stories Carousel
        if (_stories.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text('Classmate Moments', style: AppTypography.titleMedium),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 96,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              itemCount: _stories.length,
              itemBuilder: (ctx, i) {
                final s = _stories[i] as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.kidsAccent, AppColors.kidsGold],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.white,
                          backgroundImage: s['avatar_url'] != null
                              ? NetworkImage(s['avatar_url'].toString())
                              : null,
                          child: s['avatar_url'] == null
                              ? const Icon(Icons.person,
                                  color: AppColors.primary)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s['full_name']?.toString() ?? 'Student',
                        style: AppTypography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],

        // 2. Learning Challenge Card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Card(
            color: AppColors.primary.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lightbulb_rounded,
                        color: AppColors.primary, size: 32),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Today\'s Science Quiz 🚀',
                            style: AppTypography.titleMedium),
                        SizedBox(height: 2),
                        Text(
                          'Answer 3 fun questions to earn safe-learning points!',
                          style: AppTypography.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // 3. Recommended Reels Row
        if (_reels.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Safe Short Videos',
                    style: AppTypography.titleMedium),
                Text('See all (${_reels.length})',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.primary)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              itemCount: _reels.length,
              itemBuilder: (ctx, i) {
                final r = _reels[i] as Map<String, dynamic>;
                return Container(
                  width: 110,
                  margin: const EdgeInsets.only(right: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    image: r['poster_url'] != null
                        ? DecorationImage(
                            image: NetworkImage(r['poster_url'].toString()),
                            fit: BoxFit.cover)
                        : null,
                  ),
                  child: Stack(
                    children: [
                      const Center(
                        child: Icon(Icons.play_circle_fill,
                            color: Colors.white, size: 36),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 8,
                        right: 8,
                        child: Text(
                          r['caption']?.toString() ?? 'Learning Reel',
                          style: AppTypography.caption
                              .copyWith(color: Colors.white),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],

        // 4. Safe Friends Suggestions
        if (_suggested.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child:
                Text('Suggested Classmates', style: AppTypography.titleMedium),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 130,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              itemCount: _suggested.length,
              itemBuilder: (ctx, i) {
                final c = _suggested[i] as Map<String, dynamic>;
                return Container(
                  width: 120,
                  margin: const EdgeInsets.only(right: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: c['avatar_url'] != null
                            ? NetworkImage(c['avatar_url'].toString())
                            : null,
                        child: c['avatar_url'] == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        c['full_name']?.toString() ?? 'Classmate',
                        style: AppTypography.caption
                            .copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],

        // 5. Recent Safe Posts
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text('Community Updates', style: AppTypography.titleMedium),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_posts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(
              child: Text(
                'No community posts yet today. Check the Feed tab for curated learning stories! 🌱',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium,
              ),
            ),
          )
        else
          ..._posts.map((p) {
            final item = p as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundImage: item['avatar_url'] != null
                              ? NetworkImage(item['avatar_url'].toString())
                              : null,
                          child: item['avatar_url'] == null
                              ? const Icon(Icons.person, size: 18)
                              : null,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['full_name']?.toString() ?? 'Classmate',
                                  style: AppTypography.labelLarge),
                              Text(
                                  item['content_category']?.toString() ??
                                      'Learning',
                                  style: AppTypography.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (item['caption'] != null &&
                        item['caption'].toString().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(item['caption'].toString(),
                          style: AppTypography.bodyLarge),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
