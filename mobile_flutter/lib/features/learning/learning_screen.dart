import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/gradient_scaffold.dart';

class LearningScreen extends StatefulWidget {
  const LearningScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends State<LearningScreen> {
  int _points = 0;
  List<Map<String, dynamic>> _challenges = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLearningData();
  }

  Future<void> _loadLearningData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/kids/learning',
      );
      if (res['ok'] == true) {
        setState(() {
          _points = (res['points'] as num?)?.toInt() ?? 0;
          final list = (res['challenges'] as List<dynamic>?) ?? [];
          _challenges = list.whereType<Map<String, dynamic>>().toList();
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to load learning challenges.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openChallenge(Map<String, dynamic> challenge) {
    final challengeId = challenge['challenge_id'] as int? ?? 0;
    final title = challenge['title'] as String? ?? 'Learning Challenge';
    final desc = challenge['description'] as String? ?? '';
    final points = challenge['points'] as int? ?? 10;
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) {
        bool isSubmitting = false;
        String? challengeError;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.md,
                right: AppSpacing.md,
                top: AppSpacing.lg,
                bottom: bottomInset + AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(title, style: AppTypography.titleMedium),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.kidsAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          '+$points XP',
                          style: const TextStyle(
                            color: AppColors.kidsAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(desc, style: AppTypography.bodyMedium),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Your Answer or Discovery',
                      hintText: 'Type your answer here...',
                    ),
                  ),
                  if (challengeError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      challengeError!,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.error),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final ans = controller.text.trim();
                            if (ans.isEmpty) return;
                            setModalState(() => isSubmitting = true);
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              final submitRes =
                                  await widget.authState.apiClient.post(
                                '/api/mobile/v1/kids/learning/$challengeId',
                                body: {'response': ans},
                              );
                              if (ctx.mounted) {
                                Navigator.of(ctx).pop();
                              }
                              if (mounted) {
                                final correct = submitRes['correct'] == true;
                                final awarded =
                                    submitRes['points_awarded'] as int? ?? 0;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(correct
                                        ? 'Awesome job! You earned $awarded XP! 🌟'
                                        : 'Good try! Keep exploring to learn more! 🚀'),
                                    backgroundColor: correct
                                        ? AppColors.success
                                        : Colors.amber.shade800,
                                  ),
                                );
                                _loadLearningData();
                              }
                            } catch (e) {
                              setModalState(() {
                                isSubmitting = false;
                                challengeError = 'Could not submit answer.';
                              });
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Submit Solution'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Learning Lab 🔬'),
        actions: [
          IconButton(
            icon: const Icon(Icons.quiz_outlined),
            tooltip: 'Take Quiz',
            onPressed: () => Navigator.of(context).pushNamed('/kids/quiz'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadLearningData,
          ),
        ],
      ),
      body: _buildBody(),
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
              Text(_error!, style: AppTypography.bodyLarge),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: _loadLearningData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLearningData,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // XP & Level Banner
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.kidsAccent.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.military_tech_rounded,
                      size: 40, color: Colors.white),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Explorer XP',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      Text(
                        '$_points Points',
                        style: AppTypography.displayMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Keep completing daily challenges to rank up!',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Daily Challenges Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Active Challenges', style: AppTypography.titleMedium),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed('/kids/quiz'),
                icon: const Icon(Icons.bolt_rounded, size: 18),
                label: const Text('Daily Quiz'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.kidsAccent.withValues(alpha: 0.2),
                  foregroundColor: AppColors.kidsAccent,
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          if (_challenges.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded,
                        size: 48, color: AppColors.success),
                    const SizedBox(height: AppSpacing.md),
                    const Text('All Caught Up!',
                        style: AppTypography.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'You have completed all available challenges for today. Check back tomorrow!',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textMutedDark),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ..._challenges.map((c) {
              final title = c['title'] as String? ?? 'Challenge';
              final desc = c['description'] as String? ?? '';
              final points = c['points'] as int? ?? 10;
              final category = c['category'] as String? ?? 'General';
              final completed = c['completed'] == true;

              return Card(
                color: AppColors.cardDark,
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  side: BorderSide(
                    color: completed
                        ? AppColors.success.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: completed
                        ? AppColors.success.withValues(alpha: 0.2)
                        : AppColors.kidsAccent.withValues(alpha: 0.15),
                    child: Icon(
                      completed
                          ? Icons.check_circle_rounded
                          : Icons.lightbulb_outline_rounded,
                      color:
                          completed ? AppColors.success : AppColors.kidsAccent,
                    ),
                  ),
                  title: Text(title, style: AppTypography.titleSmall),
                  subtitle: Text(
                    '[$category] $desc',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textMutedDark),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.kidsAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          '+$points XP',
                          style: const TextStyle(
                            color: AppColors.kidsAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        completed
                            ? Icons.done_all_rounded
                            : Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: Colors.white38,
                      ),
                    ],
                  ),
                  onTap: completed ? null : () => _openChallenge(c),
                ),
              );
            }),
        ],
      ),
    );
  }
}
