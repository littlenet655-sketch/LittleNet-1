import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/gradient_scaffold.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  List<Map<String, dynamic>> _children = [];
  int _unread = 0;
  List<Map<String, dynamic>> _pendingFollows = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/parent/dashboard',
      );
      if (res['ok'] == true) {
        final kidsList = (res['children'] as List<dynamic>?) ?? [];
        final pendingList = (res['pending'] as List<dynamic>?) ?? [];
        setState(() {
          _children = kidsList.whereType<Map<String, dynamic>>().toList();
          _unread = (res['unread'] as num?)?.toInt() ?? 0;
          _pendingFollows =
              pendingList.whereType<Map<String, dynamic>>().toList();
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to load parent dashboard.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int get _totalOpenReviews {
    int sum = 0;
    for (final child in _children) {
      sum += (child['open_reviews'] as num?)?.toInt() ?? 0;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Parent Guardian Console'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Add Child',
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () =>
                Navigator.of(context).pushNamed('/parent/add-child'),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboard,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ElevatedButton.icon(
                          onPressed: _loadDashboard,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadDashboard,
                  color: AppColors.primary,
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      _buildAlertsSummary(),
                      const SizedBox(height: AppSpacing.md),
                      _buildSectionHeader('Managed Children', _children.length),
                      const SizedBox(height: AppSpacing.sm),
                      if (_children.isEmpty)
                        _buildEmptyChildrenState()
                      else
                        ..._children.map(_buildChildCard),
                    ],
                  ),
                ),
    );
  }

  Widget _buildAlertsSummary() {
    final openReviews = _totalOpenReviews;
    final pendingFollows = _pendingFollows.length;

    if (openReviews == 0 && pendingFollows == 0 && _unread == 0) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border:
              Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_user, color: AppColors.success, size: 28),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All Safe & Protected',
                    style: AppTypography.headingMedium.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                  Text(
                    'No open safety reviews or pending requests.',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (openReviews > 0)
          GestureDetector(
            onTap: () =>
                Navigator.of(context).pushNamed('/parent/safety-reviews'),
            child: Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border:
                    Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.security_update_warning,
                    color: AppColors.warning,
                    size: 28,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$openReviews Content Review${openReviews == 1 ? '' : 's'} Pending',
                          style: AppTypography.headingMedium.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                        Text(
                          'Moderation flagged content awaiting your decision.',
                          style: AppTypography.captionSmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: AppColors.warning,
                  ),
                ],
              ),
            ),
          ),
        if (pendingFollows > 0)
          GestureDetector(
            onTap: () =>
                Navigator.of(context).pushNamed('/parent/follow-requests'),
            child: Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_add,
                    color: AppColors.primary,
                    size: 28,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$pendingFollows Follow Request${pendingFollows == 1 ? '' : 's'} Awaiting Approval',
                          style: AppTypography.headingMedium.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          'Review connection requests before chat is enabled.',
                          style: AppTypography.captionSmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Row(
      children: [
        Text(title, style: AppTypography.headingMedium),
        const SizedBox(width: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            '$count',
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyChildrenState() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border:
            Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.family_restroom,
            size: 56,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No Children Registered',
            style: AppTypography.headingLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Add your child to configure age-appropriate controls, screen time limits, and safety filters.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
            ),
            onPressed: () =>
                Navigator.of(context).pushNamed('/parent/add-child'),
            icon: const Icon(Icons.person_add),
            label: const Text('Add Child Account'),
          ),
        ],
      ),
    );
  }

  Widget _buildChildCard(Map<String, dynamic> child) {
    final childId = child['user_id'] as int? ?? 0;
    final fullName = child['full_name'] as String? ?? 'Child';
    final username = child['username'] as String? ?? '';
    final age = child['age'] as int? ?? 0;
    final avatarUrl = child['avatar_url'] as String?;

    // Minutes today vs daily limit
    final minutesToday = (child['minutes_today'] as num?)?.toInt() ?? 0;
    final limitMap = child['limit'] as Map<String, dynamic>?;
    final dailyLimitMinutes =
        (limitMap?['daily_limit_minutes'] as num?)?.toInt() ?? 60;
    final strictMode = limitMap?['strict_mode'] == true;

    // Safety level
    final safetyMap = child['safety'] as Map<String, dynamic>?;
    final safetyLevel =
        (safetyMap?['safety_level'] as String?)?.toUpperCase() ?? 'STRICT';

    // Presence
    final presenceMap = child['presence'] as Map<String, dynamic>?;
    final isOnline = presenceMap?['online'] == true;

    // Open reviews
    final openReviews = (child['open_reviews'] as num?)?.toInt() ?? 0;

    // Quiz activity
    final quizMap = child['quiz_7d'] as Map<String, dynamic>?;
    final quizAccuracy = (quizMap?['accuracy'] as num?)?.toInt() ?? 0;
    final quizAttempted = (quizMap?['attempted'] as num?)?.toInt() ?? 0;

    final progressRatio = (dailyLimitMinutes > 0)
        ? (minutesToday / dailyLimitMinutes).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: openReviews > 0
              ? AppColors.warning.withValues(alpha: 0.4)
              : AppColors.surfaceLight.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.surfaceLight,
                backgroundImage:
                    avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? Text(
                        fullName.isNotEmpty ? fullName[0].toUpperCase() : 'C',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            fullName,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.headingMedium,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isOnline
                                ? AppColors.success.withValues(alpha: 0.2)
                                : AppColors.surfaceLight.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            isOnline ? 'ONLINE' : 'OFFLINE',
                            style: AppTypography.captionSmall.copyWith(
                              color: isOnline
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@$username  •  Age $age  •  $safetyLevel Safety',
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (openReviews > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.flag,
                        size: 12,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$openReviews REVIEW',
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Screen time progress
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Screen Time Today',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$minutesToday / $dailyLimitMinutes min ${strictMode ? "(Strict)" : ""}',
                style: AppTypography.captionSmall.copyWith(
                  color: progressRatio >= 1.0
                      ? AppColors.error
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: progressRatio,
              minHeight: 8,
              backgroundColor: AppColors.surfaceLight.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                progressRatio >= 1.0
                    ? AppColors.error
                    : progressRatio >= 0.8
                        ? AppColors.warning
                        : AppColors.success,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Quiz performance summary
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.school_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  quizAttempted > 0
                      ? '7-Day Learning: $quizAccuracy% accuracy across $quizAttempted questions'
                      : '7-Day Learning: No quizzes taken this week',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      '/parent/controls',
                      arguments: childId,
                    );
                  },
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('Controls & Limits'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.warning,
                  side: const BorderSide(color: AppColors.warning),
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pushNamed(
                    '/parent/safety-reviews',
                    arguments: childId,
                  );
                },
                icon: const Icon(Icons.shield_outlined, size: 16),
                label: const Text('Safety Queue'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
