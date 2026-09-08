import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/models/user.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/gradient_scaffold.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  final ImagePicker _picker = ImagePicker();

  String get _currentMode {
    switch (_tabController.index) {
      case 0:
        return 'kids';
      case 1:
        return 'parent';
      case 2:
        return 'admin';
      default:
        return 'kids';
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {
          _error = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handlePasswordLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/auth/login',
        body: {
          'identifier': _identifierController.text.trim(),
          'password': _passwordController.text,
          'mode': _currentMode,
        },
      );

      if (res['ok'] == true && res['token'] != null && res['user'] != null) {
        final user = User.fromJson(res['user'] as Map<String, dynamic>);
        widget.authState.setAuthenticated(user, res['token'].toString());
        if (!mounted) return;
        _navigateHomeForUser(user);
        return;
      }
    } on ApiException catch (e) {
      if (e.statusCode == 428 && e.payload?['pending_token'] != null) {
        // Parent verification needed: redirect to OTP / Liveness
        final pending = e.payload!['pending_token'].toString();
        widget.authState.setPendingVerification(pending);
        if (!mounted) return;
        Navigator.of(context).pushNamed(
          '/parent/otp',
          arguments: {'pending_token': pending},
        );
        return;
      }
      setState(() {
        _error = _humanErrorMessage(e.message);
      });
    } catch (e) {
      setState(() {
        _error =
            'Unable to connect to LittleNet. Please check your internet connection.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleFaceLogin() async {
    final identifier = _identifierController.text.trim();
    if (identifier.isEmpty) {
      setState(() {
        _error = 'Please enter your username or email first to use Face Login.';
      });
      return;
    }

    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 85,
      );
      if (photo == null) return;

      setState(() {
        _isLoading = true;
        _error = null;
      });

      final bytes = await photo.readAsBytes();
      final photoB64 = base64Encode(bytes);

      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/auth/face-login',
        body: {
          'identifier': identifier,
          'mode': _currentMode,
          'photo_b64': photoB64,
        },
      );

      if (res['ok'] == true && res['token'] != null && res['user'] != null) {
        final user = User.fromJson(res['user'] as Map<String, dynamic>);
        widget.authState.setAuthenticated(user, res['token'].toString());
        if (!mounted) return;
        _navigateHomeForUser(user);
        return;
      }
    } on ApiException catch (e) {
      setState(() {
        _error = _humanErrorMessage(e.message);
      });
    } catch (_) {
      setState(() {
        _error = 'Face verification failed. Please try password login.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _navigateHomeForUser(User user) {
    if (user.isChild) {
      Navigator.of(context).pushReplacementNamed('/kids/home');
    } else if (user.isParent) {
      Navigator.of(context).pushReplacementNamed('/parent/dashboard');
    } else if (user.isAdmin) {
      Navigator.of(context).pushReplacementNamed('/moderator/queue');
    }
  }

  String _humanErrorMessage(String code) {
    switch (code) {
      case 'invalid_credentials':
        return 'Incorrect username or password. Please try again.';
      case 'wrong_mode':
        return 'Account not registered for this role. Switch tabs above.';
      case 'account_inactive':
        return 'This account is inactive. Please contact your parent or admin.';
      case 'account_not_found':
        return 'No account found with this username or email.';
      case 'live_camera_photo_required':
        return 'Camera photo required for Face Login.';
      case 'face_login_failed':
        return 'Face not recognized. Please use password login.';
      default:
        return 'Login failed. Please check your credentials.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Brand Header
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      size: 48,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'LittleNet',
                  style: AppTypography.display,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Safe, positive, parent-guided social learning',
                  style: AppTypography.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),

                // Card Container
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Role Switcher Tabs
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: AppRadius.roundedSm,
                            ),
                            child: TabBar(
                              controller: _tabController,
                              indicatorSize: TabBarIndicatorSize.tab,
                              dividerColor: Colors.transparent,
                              indicator: BoxDecoration(
                                color: _currentMode == 'kids'
                                    ? AppColors.kidsAccent
                                    : _currentMode == 'parent'
                                        ? AppColors.parentAccent
                                        : AppColors.moderatorAccent,
                                borderRadius: AppRadius.roundedSm,
                              ),
                              labelColor: Colors.white,
                              unselectedLabelColor: AppColors.textSecondary,
                              labelStyle: AppTypography.labelLarge,
                              tabs: const [
                                Tab(text: 'Kids'),
                                Tab(text: 'Parent'),
                                Tab(text: 'Admin'),
                              ],
                            ),
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
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline,
                                      color: AppColors.error, size: 20),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: AppTypography.bodyMedium
                                          .copyWith(color: AppColors.error),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],

                          // Input Fields
                          AppTextField(
                            controller: _identifierController,
                            label: _currentMode == 'parent'
                                ? 'Parent Email'
                                : 'Username',
                            hint: _currentMode == 'parent'
                                ? 'parent@example.com'
                                : 'Enter your username',
                            prefixIcon: _currentMode == 'parent'
                                ? Icons.email_outlined
                                : Icons.person_outline,
                            keyboardType: _currentMode == 'parent'
                                ? TextInputType.emailAddress
                                : TextInputType.text,
                            textInputAction: TextInputAction.next,
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Please enter your username or email';
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
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _handlePasswordLogin(),
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'Please enter your password';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          // Submit Button
                          AppButton(
                            text: 'Sign In',
                            isLoading: _isLoading,
                            onPressed: _handlePasswordLogin,
                          ),

                          // Face Login Action for Child & Parent
                          if (_currentMode != 'admin') ...[
                            const SizedBox(height: AppSpacing.sm),
                            AppButton(
                              text: 'Face Login',
                              variant: ButtonVariant.secondary,
                              icon: Icons.face_outlined,
                              isLoading: _isLoading,
                              onPressed: _handleFaceLogin,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Parent Registration CTA
                if (_currentMode == 'parent') ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account?",
                          style: AppTypography.bodyMedium),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pushNamed('/parent/signup');
                        },
                        child: const Text('Register as Parent'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
