import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/gradient_scaffold.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<Map<String, dynamic>> _quizzes = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _submitting = false;
  String? _error;
  bool _isMandatory = false;

  int? _selectedOptionIndex;
  int? _correctOptionIndex;
  String? _serverExplanation;
  String? _answerError;
  bool _answered = false;
  int _score = 0;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  Future<void> _loadQuiz() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentIndex = 0;
      _selectedOptionIndex = null;
      _correctOptionIndex = null;
      _serverExplanation = null;
      _answerError = null;
      _answered = false;
      _score = 0;
      _completed = false;
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/kids/quiz',
      );
      if (res['ok'] == true) {
        final list = (res['quizzes'] as List<dynamic>?) ?? [];
        final loaded = list.whereType<Map<String, dynamic>>().toList();
        final required =
            res['required'] == true || res['reason'] == 'feed_break';

        setState(() {
          _quizzes = loaded;
          _isMandatory = required;
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to load quizzes.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitOption(int optionIndex) async {
    if (_answered || _submitting || _currentIndex >= _quizzes.length) return;

    final q = _quizzes[_currentIndex];
    final options =
        (q['options'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            [];
    final selectedAnswer = (optionIndex >= 0 && optionIndex < options.length)
        ? options[optionIndex]
        : optionIndex.toString();
    final quizId = q['quiz_id'] as int?;

    setState(() {
      _selectedOptionIndex = optionIndex;
      _answerError = null;
      _submitting = true;
    });

    try {
      if (quizId != null) {
        final res = await widget.authState.apiClient.post(
          '/api/mobile/v1/kids/quiz/$quizId/answer',
          body: {'answer': selectedAnswer},
        );
        final isCorrect = res['correct'] == true;
        final serverExplanation = res['explanation']?.toString();
        final correctAnswer = res['correct_answer']?.toString();

        int correctIdx = -1;
        if (correctAnswer != null) {
          correctIdx =
              options.indexWhere((opt) => opt.trim() == correctAnswer.trim());
        }
        if (correctIdx == -1) {
          correctIdx = (q['correct_option_index'] as num?)?.toInt() ??
              (isCorrect ? optionIndex : -1);
        }

        if (mounted) {
          setState(() {
            _answered = true;
            _submitting = false;
            _serverExplanation = serverExplanation;
            _correctOptionIndex = correctIdx;
            if (isCorrect) _score++;
          });
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _selectedOptionIndex = null;
          _answerError = e.message == 'quiz_not_available'
              ? 'This question is no longer available. Reload the quiz.'
              : 'We could not save your answer. Check your connection and try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _selectedOptionIndex = null;
          _answerError =
              'We could not save your answer. Check your connection and try again.';
        });
      }
    }
  }

  void _nextQuestion() {
    if (_currentIndex + 1 < _quizzes.length) {
      setState(() {
        _currentIndex++;
        _selectedOptionIndex = null;
        _correctOptionIndex = null;
        _serverExplanation = null;
        _answerError = null;
        _answered = false;
      });
    } else {
      setState(() {
        _completed = true;
      });
    }
  }

  void _finishQuiz() {
    if (_isMandatory) {
      Navigator.of(context).pushNamedAndRemoveUntil('/kids/home', (_) => false);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _completed || !_isMandatory || _quizzes.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_completed || !_isMandatory || _quizzes.isEmpty) {
          Navigator.of(context).pop();
        }
      },
      child: GradientScaffold(
        appBar: AppBar(
          automaticallyImplyLeading: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            tooltip: 'Back to Feed',
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pushReplacementNamed('/kids/home');
              }
            },
          ),
          title: Text(_isMandatory ? 'Brain Break Quiz 🧠' : 'Brain Quiz 🧠'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Reload',
              onPressed: _loadQuiz,
            ),
          ],
        ),
        body: _buildBody(),
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
              Text(_error!, style: AppTypography.bodyLarge),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: _loadQuiz,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_quizzes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.sentiment_satisfied_alt_rounded,
                  size: 56, color: AppColors.kidsAccent),
              const SizedBox(height: AppSpacing.md),
              const Text('No Quizzes Right Now',
                  style: AppTypography.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'You have completed all active quizzes! Check the Learning Lab for more challenges.',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textMutedDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton.icon(
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    Navigator.of(context).pushReplacementNamed('/kids/home');
                  }
                },
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back to Home Feed'),
              ),
            ],
          ),
        ),
      );
    }

    if (_completed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.emoji_events_rounded,
                    size: 64, color: AppColors.success),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('Quiz Completed! 🚀',
                  style: AppTypography.displaySmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'You scored $_score / ${_quizzes.length}',
                style: AppTypography.titleLarge.copyWith(
                  color: AppColors.kidsAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _score == _quizzes.length
                    ? 'Perfect score! You are a master explorer! 🌟'
                    : 'Great effort! Practice makes progress! Keep it up! 💡',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textMutedDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton(
                onPressed: _finishQuiz,
                child: Text(
                    _isMandatory ? 'Continue Browsing 🚀' : 'Back to Learning'),
              ),
            ],
          ),
        ),
      );
    }

    final currentQuiz = _quizzes[_currentIndex];
    final question = currentQuiz['question'] as String? ?? 'Question';
    final options = (currentQuiz['options'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final explanation =
        _serverExplanation ?? currentQuiz['explanation'] as String?;
    final correctIdx = _correctOptionIndex ??
        (currentQuiz['correct_option_index'] as num?)?.toInt() ??
        0;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: (_currentIndex + 1) / _quizzes.length,
            backgroundColor: AppColors.cardBorder,
            color: AppColors.kidsAccent,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Question ${_currentIndex + 1} of ${_quizzes.length}',
            style:
                AppTypography.caption.copyWith(color: AppColors.textMutedDark),
          ),
          const SizedBox(height: AppSpacing.md),

          // Question Card
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Text(
              question,
              style: AppTypography.titleMedium.copyWith(
                height: 1.4,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Options
          Expanded(
            child: ListView.separated(
              itemCount: options.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) {
                Color border = AppColors.cardBorder;
                Color bg = AppColors.surface;

                if (_answered) {
                  if (i == correctIdx) {
                    border = AppColors.success;
                    bg = AppColors.success.withValues(alpha: 0.15);
                  } else if (i == _selectedOptionIndex) {
                    border = AppColors.error;
                    bg = AppColors.error.withValues(alpha: 0.15);
                  }
                } else if (i == _selectedOptionIndex) {
                  border = AppColors.primary;
                  bg = AppColors.primary.withValues(alpha: 0.08);
                }

                return GestureDetector(
                  onTap: _answered ? null : () => _submitOption(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: border, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.background,
                          child: Text(
                            String.fromCharCode(65 + i),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            options[i],
                            style: AppTypography.bodyMedium
                                .copyWith(color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          if (_answerError != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _answerError!,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
          ],

          // Feedback & Next Button
          if (_answered) ...[
            if (explanation != null && explanation.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Text(
                  '💡 $explanation',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            ElevatedButton(
              onPressed: _nextQuestion,
              child: Text(
                _currentIndex + 1 < _quizzes.length
                    ? 'Next Question ➔'
                    : 'See Results 🏆',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
