import 'dart:async';
import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';

class ForgotPasswordSheet extends StatefulWidget {
  const ForgotPasswordSheet({
    super.key,
    required this.authState,
    this.initialIdentifier,
  });

  final AuthState authState;
  final String? initialIdentifier;

  static Future<void> show(
    BuildContext context, {
    required AuthState authState,
    String? initialIdentifier,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ForgotPasswordSheet(
        authState: authState,
        initialIdentifier: initialIdentifier,
      ),
    );
  }

  @override
  State<ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<ForgotPasswordSheet> {
  int _step = 1; // 1: Identifier, 2: OTP + New Password, 3: Success
  final _identifierController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  int? _userId;
  String? _maskedEmail;
  bool _isParentProxy = false;

  Timer? _countdownTimer;
  int _countdown = 60;
  bool get _canResend => _countdown == 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialIdentifier != null && widget.initialIdentifier!.isNotEmpty) {
      _identifierController.text = widget.initialIdentifier!;
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _identifierController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        if (mounted) setState(() => _countdown--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _handleRequestOtp() async {
    final ident = _identifierController.text.trim();
    if (ident.isEmpty) {
      setState(() => _error = 'Please enter your username or email address.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/auth/forgot-password',
        body: {'identifier': ident},
      );

      if (res['ok'] == true) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _userId = res['user_id'] as int?;
          _maskedEmail = res['masked_email'] as String?;
          _isParentProxy = res['is_parent_proxy'] == true;
          _step = 2;
        });
        _startCountdown();
      } else {
        setState(() {
          _isLoading = false;
          _error = res['error']?.toString() ?? 'Unable to send reset code.';
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.payload?['error']?.toString() ?? e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Network error. Please verify your connection.';
      });
    }
  }

  Future<void> _handleResetPassword() async {
    final code = _otpController.text.trim();
    final newPwd = _newPasswordController.text;
    final confirmPwd = _confirmPasswordController.text;

    if (code.length != 6) {
      setState(() => _error = 'Please enter the 6-digit verification code.');
      return;
    }
    if (newPwd.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters long.');
      return;
    }
    if (newPwd != confirmPwd) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/auth/reset-password',
        body: {
          'user_id': _userId,
          'code': code,
          'new_password': newPwd,
        },
      );

      if (res['ok'] == true) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _step = 3;
        });
      } else {
        setState(() {
          _isLoading = false;
          _error = res['error']?.toString() ?? 'Failed to reset password.';
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.payload?['error']?.toString() ?? e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to reset password. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: bottomInset),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle Bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Step content
                if (_step == 1) _buildStep1Identifier(),
                if (_step == 2) _buildStep2OtpAndNewPassword(),
                if (_step == 3) _buildStep3Success(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep1Identifier() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.lock_reset_rounded,
                color: AppColors.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reset Password',
                    style: AppTypography.headingMedium,
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Enter your username or email to receive a code',
                    style: AppTypography.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.textSecondary),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        if (_error != null) ...[
          _buildErrorBox(_error!),
          const SizedBox(height: AppSpacing.md),
        ],

        AppTextField(
          controller: _identifierController,
          label: 'Username or Email',
          hint: 'e.g. kid_alex or parent@example.com',
          prefixIcon: Icons.account_circle_outlined,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _handleRequestOtp(),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'For kids without an email, the code will be sent to your linked parent.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.lg),

        AppButton(
          text: 'Send Verification Code',
          isLoading: _isLoading,
          onPressed: _handleRequestOtp,
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  Widget _buildStep2OtpAndNewPassword() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => setState(() => _step = 1),
            ),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter Code & New Password',
                    style: AppTypography.headingMedium,
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Check your email inbox for the 6-digit code',
                    style: AppTypography.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.textSecondary),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Info Banner
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.parentAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.parentAccent.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.mark_email_read_outlined, color: AppColors.parentAccent, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _isParentProxy
                      ? 'Code sent to parent email: ${_maskedEmail ?? "registered email"}'
                      : 'Code sent to: ${_maskedEmail ?? "your registered email"}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        if (_error != null) ...[
          _buildErrorBox(_error!),
          const SizedBox(height: AppSpacing.md),
        ],

        AppTextField(
          controller: _otpController,
          label: '6-Digit Verification Code',
          hint: '123456',
          prefixIcon: Icons.security_rounded,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),

        AppTextField(
          controller: _newPasswordController,
          label: 'New Password',
          hint: 'At least 8 characters',
          prefixIcon: Icons.lock_outline_rounded,
          isPassword: true,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),

        AppTextField(
          controller: _confirmPasswordController,
          label: 'Confirm New Password',
          hint: 'Re-enter your new password',
          prefixIcon: Icons.lock_reset_rounded,
          isPassword: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _handleResetPassword(),
        ),
        const SizedBox(height: AppSpacing.sm),

        // Resend Timer Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _canResend ? _handleRequestOtp : null,
              child: Text(
                _canResend ? 'Resend Code' : 'Resend in ${_countdown}s',
                style: AppTypography.bodySmall.copyWith(
                  color: _canResend ? AppColors.primary : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        AppButton(
          text: 'Save New Password',
          isLoading: _isLoading,
          onPressed: _handleResetPassword,
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  Widget _buildStep3Success() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 48,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'Password Reset Complete!',
            style: AppTypography.headingMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Your LittleNet password has been successfully updated. You can now sign in with your new credentials.',
            style: AppTypography.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            text: 'Return to Sign In',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              msg,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
