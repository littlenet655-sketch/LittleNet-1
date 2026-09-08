import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../widgets.dart';

class GateAwareError extends StatelessWidget {
  const GateAwareError({
    super.key,
    required this.api,
    required this.error,
    required this.onResolved,
  });

  final ApiClient api;
  final Object error;
  final VoidCallback onResolved;

  @override
  Widget build(BuildContext context) {
    final apiError = error is ApiException ? error as ApiException : null;
    final code = apiError?.message;
    final icon = switch (code) {
      'face_enrollment_required' => Icons.face_retouching_natural_rounded,
      'quiz_required' || 'onboarding_quiz_required' => Icons.school_rounded,
      'screen_time_limit' => Icons.bedtime_rounded,
      'quiet_hours' => Icons.nights_stay_rounded,
      'disabled_by_parent' => Icons.shield_rounded,
      _ => Icons.cloud_off_rounded,
    };
    final canResolve = code == 'face_enrollment_required' ||
        code == 'quiz_required' ||
        code == 'onboarding_quiz_required';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 68, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 18),
            Text(
              friendlyError(error),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (code == 'screen_time_limit')
              const Text(
                'Your safe space is taking a rest. Parent Mode decides when you can come back.',
                textAlign: TextAlign.center,
              )
            else if (code == 'quiet_hours')
              const Text(
                'It is quiet time now. LittleNet will be ready again after the parent-set break.',
                textAlign: TextAlign.center,
              )
            else if (code == 'disabled_by_parent')
              const Text(
                'This feature is currently off in Parent Mode.',
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 20),
            if (canResolve)
              FilledButton.icon(
                onPressed: () async {
                  final ok = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => code == 'face_enrollment_required'
                          ? FaceEnrollmentScreen(api: api)
                          : QuizGateScreen(api: api),
                    ),
                  );
                  if (ok == true) onResolved();
                },
                icon: Icon(code == 'face_enrollment_required'
                    ? Icons.camera_alt_rounded
                    : Icons.play_arrow_rounded),
                label: Text(code == 'face_enrollment_required'
                    ? 'Set Up Face ID'
                    : 'Start Quiz'),
              )
            else
              OutlinedButton.icon(
                onPressed: onResolved,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Check again'),
              ),
          ],
        ),
      ),
    );
  }
}

class FaceEnrollmentScreen extends StatefulWidget {
  const FaceEnrollmentScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen> {
  bool busy = false;
  String? message;

  Future<void> _capture() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 90,
      maxWidth: 1280,
    );
    if (picked == null) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final data = await widget.api.enrollChildFace(File(picked.path));
      if (!mounted) return;
      if (data['quiz_required'] == true) {
        final ok = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => QuizGateScreen(api: widget.api)),
        );
        if (ok == true && mounted) Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      setState(() => message = friendlyError(e));
    } catch (_) {
      setState(() => message = 'Face setup could not connect. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kids Face ID')),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(42),
              ),
              child: const Icon(
                Icons.face_retouching_natural_rounded,
                size: 78,
                color: Color(0xFF2563EB),
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'Set up your LittleNet Face ID',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            const Text(
              'Use the front camera in good light. Look directly at the screen and keep your face clearly visible.',
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 18),
              Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: busy ? null : _capture,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt_rounded),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Open Front Camera'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QuizGateScreen extends StatefulWidget {
  const QuizGateScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<QuizGateScreen> createState() => _QuizGateScreenState();
}

class _QuizGateScreenState extends State<QuizGateScreen> {
  Future<Map<String, dynamic>>? future;
  int index = 0;
  bool submitting = false;
  String? feedback;
  int score = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      future = widget.api.getJson('/api/mobile/v1/kids/quiz');
      index = 0;
      feedback = null;
      score = 0;
    });
  }

  Future<void> _answer(Map<String, dynamic> quiz, String answer) async {
    setState(() {
      submitting = true;
      feedback = null;
    });
    try {
      final result = await widget.api.postJson(
        '/api/mobile/v1/kids/quiz/${quiz['quiz_id']}/answer',
        {'answer': answer},
      );
      final correct = result['correct'] == true;
      if (correct) score++;
      if (!mounted) return;
      final quizzes = listMaps((await future)?['quizzes']);
      setState(() {
        feedback = correct
            ? 'Great job! +${result['xp'] ?? 0} XP'
            : 'Nice try! ${result['explanation'] ?? ''}';
      });
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      if (index + 1 < quizzes.length) {
        setState(() {
          index++;
          feedback = null;
        });
      } else {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      setState(() => feedback = friendlyError(e));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LittleNet Brain Break')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(friendlyError(snapshot.error!)),
              ),
            );
          }
          final quizzes = listMaps(snapshot.data?['quizzes']);
          if (quizzes.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Text(
                  'The required quiz is temporarily unavailable. The safety break remains active.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final safeIndex = index.clamp(0, quizzes.length - 1);
          final quiz = quizzes[safeIndex];
          final options = (quiz['options'] as List? ?? const []).map((e) => e.toString()).toList();
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              LinearProgressIndicator(value: (safeIndex + 1) / quizzes.length),
              const SizedBox(height: 24),
              Text(
                'Question ${safeIndex + 1} of ${quizzes.length}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 10),
              Text(
                quiz['question']?.toString() ?? '',
                style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 22),
              for (final option in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton(
                    onPressed: submitting ? null : () => _answer(quiz, option),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    ),
                    child: Text(option, style: const TextStyle(fontSize: 17)),
                  ),
                ),
              if (feedback != null) ...[
                const SizedBox(height: 10),
                Text(
                  feedback!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
