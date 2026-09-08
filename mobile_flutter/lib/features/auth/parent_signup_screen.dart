import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/gradient_scaffold.dart';

class ParentSignupScreen extends StatefulWidget {
  const ParentSignupScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<ParentSignupScreen> createState() => _ParentSignupScreenState();
}

class _ParentSignupScreenState extends State<ParentSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/auth/parent/register',
        body: {
          'full_name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'confirm_password': _confirmPasswordController.text,
        },
      );

      if (res['ok'] == true && res['pending_token'] != null) {
        final pending = res['pending_token'].toString();
        widget.authState.setPendingVerification(pending);
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(
          '/parent/otp',
          arguments: {
            'pending_token': pending,
            'email': _emailController.text.trim(),
          },
        );
        return;
      }
    } on ApiException catch (e) {
      setState(() {
        _error = _formatError(e.message);
      });
    } catch (_) {
      setState(() {
        _error = 'Unable to connect to LittleNet. Please check your network.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatError(String code) {
    if (code.contains('already registered') || code.contains('email_exists')) {
      return 'This email address is already registered. Please sign in.';
    }
    if (code.contains('password_too_short')) {
      return 'Password must be at least 8 characters long.';
    }
    if (code.contains('passwords_do_not_match')) {
      return 'Passwords do not match.';
    }
    return code;
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Parent Registration'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Step Indicator
                Row(
                  children: [
                    _stepCircle('1', isActive: true, label: 'Account'),
                    _stepLine(),
                    _stepCircle('2', isActive: false, label: 'Email OTP'),
                    _stepLine(),
                    _stepCircle('3', isActive: false, label: 'Face ID'),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                // Form Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Create Parent Account',
                            style: AppTypography.titleLarge,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          const Text(
                            'As a parent or guardian, you will manage safety settings, approve connections, and supervise screen time.',
                            style: AppTypography.bodyMedium,
                          ),
                          const SizedBox(height: AppSpacing.lg),
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
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          AppTextField(
                            controller: _nameController,
                            label: 'Full Name',
                            prefixIcon: Icons.person_outline,
                            textInputAction: TextInputAction.next,
                            validator: (val) {
                              if (val == null || val.trim().length < 2) {
                                return 'Please enter your full name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppTextField(
                            controller: _emailController,
                            label: 'Email Address',
                            prefixIcon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            validator: (val) {
                              if (val == null ||
                                  !val.contains('@') ||
                                  !val.contains('.')) {
                                return 'Please enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppTextField(
                            controller: _passwordController,
                            label: 'Password',
                            prefixIcon: Icons.lock_outline,
                            isPassword: true,
                            textInputAction: TextInputAction.next,
                            validator: (val) {
                              if (val == null || val.length < 8) {
                                return 'Password must be at least 8 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppTextField(
                            controller: _confirmPasswordController,
                            label: 'Confirm Password',
                            prefixIcon: Icons.lock_outline,
                            isPassword: true,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _handleRegister(),
                            validator: (val) {
                              if (val != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          AppButton(
                            text: 'Continue to Email Verification',
                            isLoading: _isLoading,
                            onPressed: _handleRegister,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already registered?',
                        style: AppTypography.bodyMedium),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Sign In'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepCircle(String number,
      {required bool isActive, required String label}) {
    return Column(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: isActive ? AppColors.primary : AppColors.cardBorder,
          child: Text(
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
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _stepLine() {
    return Expanded(
      child: Container(
        height: 2,
        color: AppColors.cardBorder,
        margin: const EdgeInsets.only(bottom: 16),
      ),
    );
  }
}
