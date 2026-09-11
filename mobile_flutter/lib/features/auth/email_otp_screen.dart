import 'dart:async';
import 'package:flutter/material.dart';
import '../../api.dart';
import '../../brand_logo.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/gradient_scaffold.dart';

class EmailOtpScreen extends StatefulWidget {
  const EmailOtpScreen({
    super.key,
    required this.authState,
    required this.pendingToken,
    this.email,
  });

  final AuthState authState;
  final String pendingToken;
  final String? email;

  @override
  State<EmailOtpScreen> createState() => _EmailOtpScreenState();
}

class _EmailOtpScreenState extends State<EmailOtpScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  late String _currentPendingToken;
  bool _isLoading = false;
  bool _isResending = false;
  String? _error;
  String? _successMessage;

  Timer? _timer;
  int _countdown = 60;
  bool get _canResend => _countdown == 0;

  @override
  void initState() {
    super.initState();
    _currentPendingToken = widget.pendingToken;
    _startCountdown();
  }

  void _startCountdown() {
    _countdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown > 0) {
        if (mounted) setState(() => _countdown--);
      } else {
        t.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text.trim()).join();

  Future<void> _handleVerify() async {
    if (_otp.length < 6) {
      setState(() =>
          _error = 'Please enter all 6 digits of the email verification code.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/auth/parent/verify-email',
        body: {
          'pending_token': _currentPendingToken,
          'otp': _otp,
        },
      );

      if (res['ok'] == true && res['pending_token'] != null) {
        final nextPending = res['pending_token'].toString();
        widget.authState.setPendingVerification(nextPending);
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(
          '/parent/liveness',
          arguments: {
            'pending_token': nextPending,
            'email': widget.email,
          },
        );
        return;
      }
    } on ApiException catch (e) {
      setState(() {
        if (e.message.contains('expired')) {
          _error = 'Verification code has expired. Please tap Resend Code.';
        } else if (e.message.contains('invalid_otp') ||
            e.message.contains('incorrect')) {
          _error =
              'Incorrect 6-digit code. Please check your inbox and try again.';
        } else {
          _error = e.message;
        }
      });
    } catch (_) {
      setState(() =>
          _error = 'Unable to connect to LittleNet server. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleResend() async {
    if (!_canResend || _isResending) return;

    setState(() {
      _isResending = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/auth/parent/resend-email',
        body: {'pending_token': _currentPendingToken},
      );

      if (res['ok'] == true) {
        setState(() {
          _successMessage =
              'A new 6-digit verification code has been sent to your email.';
        });
        _startCountdown();
      }
    } on ApiException catch (e) {
      setState(() {
        if (e.statusCode == 503 || e.message.contains('email_send_failed')) {
          _error =
              'Email service temporarily unavailable. Please try again in a few minutes.';
        } else if (e.message.contains('pending_verification_expired')) {
          _error =
              'Your registration session has expired. Please sign up again.';
        } else if (e.message.contains('rate_limit') || e.statusCode == 429) {
          _error = 'Too many resend attempts. Please wait before retrying.';
        } else {
          _error = e.message;
        }
      });
    } catch (_) {
      setState(() =>
          _error = 'Failed to resend code. Please wait a moment and retry.');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Email Verification'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Brand Header
                const Center(
                  child: LittleNetAppLogo(size: 48, elevation: 2),
                ),
                const SizedBox(height: AppSpacing.md),

                // Step Indicator
                Row(
                  children: [
                    _stepCircle('1', isDone: true, label: 'Account'),
                    _stepLine(isDone: true),
                    _stepCircle('2', isActive: true, label: 'Email OTP'),
                    _stepLine(),
                    _stepCircle('3', isActive: false, label: 'Face ID'),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                // Card Container
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.mark_email_read_outlined,
                              size: 40,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const Text(
                          'Enter Email OTP',
                          style: AppTypography.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          widget.email != null
                              ? 'We sent a 6-digit verification code to:\n${widget.email}'
                              : 'Enter the 6-digit code sent to your parent email address.',
                          style: AppTypography.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Error Banner
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: AppRadius.roundedSm,
                              border: Border.all(
                                  color:
                                      AppColors.error.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              _error!,
                              style: AppTypography.bodyMedium
                                  .copyWith(color: AppColors.error),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],

                        // Success Banner
                        if (_successMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: AppRadius.roundedSm,
                              border: Border.all(
                                  color:
                                      AppColors.success.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              _successMessage!,
                              style: AppTypography.bodyMedium
                                  .copyWith(color: AppColors.success),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],

                        // 6-digit inputs
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(6, (index) {
                            return SizedBox(
                              width: 46,
                              height: 54,
                              child: TextField(
                                controller: _controllers[index],
                                focusNode: _focusNodes[index],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                maxLength: 1,
                                style: const TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  counterText: '',
                                  contentPadding: EdgeInsets.zero,
                                  border: OutlineInputBorder(
                                    borderRadius: AppRadius.roundedMd,
                                    borderSide: const BorderSide(
                                        color: AppColors.cardBorder,
                                        width: 1.5),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: AppRadius.roundedMd,
                                    borderSide: const BorderSide(
                                        color: AppColors.primary, width: 2),
                                  ),
                                ),
                                onChanged: (value) {
                                  if (value.isNotEmpty && index < 5) {
                                    _focusNodes[index + 1].requestFocus();
                                  } else if (value.isEmpty && index > 0) {
                                    _focusNodes[index - 1].requestFocus();
                                  }
                                  if (_otp.length == 6) {
                                    _handleVerify();
                                  }
                                },
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        AppButton(
                          text: 'Verify Code',
                          isLoading: _isLoading,
                          onPressed: _handleVerify,
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Resend Section
                        Center(
                          child: _canResend
                              ? TextButton.icon(
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: _isResending
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Text('Resend Code'),
                                  onPressed:
                                      _isResending ? null : _handleResend,
                                )
                              : Text(
                                  'Resend code in ${_countdown}s',
                                  style: AppTypography.caption
                                      .copyWith(color: AppColors.textSecondary),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepCircle(String number,
      {bool isActive = false, bool isDone = false, required String label}) {
    final color = isDone
        ? AppColors.success
        : isActive
            ? AppColors.primary
            : AppColors.cardBorder;
    return Column(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: color,
          child: isDone
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text(
                  number,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.white : AppColors.textSecondary,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isActive ? AppColors.primary : AppColors.textMuted,
            fontWeight:
                isActive || isDone ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _stepLine({bool isDone = false}) {
    return Expanded(
      child: Container(
        height: 2,
        color: isDone ? AppColors.success : AppColors.cardBorder,
        margin: const EdgeInsets.only(bottom: 16),
      ),
    );
  }
}
