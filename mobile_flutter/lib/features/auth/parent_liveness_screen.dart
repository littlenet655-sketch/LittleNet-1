import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../api.dart';
import '../../brand_logo.dart';
import '../../core/auth/auth_state.dart';
import '../../core/models/user.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/gradient_scaffold.dart';

class ParentLivenessScreen extends StatefulWidget {
  const ParentLivenessScreen({
    super.key,
    required this.authState,
    required this.pendingToken,
    this.email,
  });

  final AuthState authState;
  final String pendingToken;
  final String? email;

  @override
  State<ParentLivenessScreen> createState() => _ParentLivenessScreenState();
}

class _ParentLivenessScreenState extends State<ParentLivenessScreen> {
  final ImagePicker _picker = ImagePicker();

  Uint8List? _capturedPhotoBytes;
  bool _isCapturing = false;
  bool _isVerifying = false;
  String? _error;
  String? _statusMessage;

  Future<void> _takeSelfie() async {
    setState(() {
      _isCapturing = true;
      _error = null;
      _statusMessage = null;
    });

    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 960,
        maxHeight: 960,
        imageQuality: 90,
      );

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          _capturedPhotoBytes = bytes;
          _statusMessage =
              'Selfie captured. Tap "Verify & Complete" to verify adult face.';
        });
      }
    } catch (_) {
      setState(() {
        _error =
            'Unable to access camera. Please allow camera permissions in settings.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<void> _handleVerifyLiveness() async {
    if (_capturedPhotoBytes == null) {
      setState(() => _error = 'Please take a live selfie before verifying.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
      _statusMessage =
          'Analyzing facial liveness and adult age with AI safety model...';
    });

    try {
      final photoB64 = base64Encode(_capturedPhotoBytes!);
      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/auth/parent/verify-liveness',
        body: {
          'pending_token': widget.pendingToken,
          'photo_b64': photoB64,
        },
      );

      if (res['ok'] == true && res['token'] != null && res['user'] != null) {
        final user = User.fromJson(res['user'] as Map<String, dynamic>);
        widget.authState.setAuthenticated(user, res['token'].toString());

        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/parent/dashboard',
          (route) => false,
        );
        return;
      }
    } on ApiException catch (e) {
      setState(() {
        if (e.message.contains('adult_liveness_failed') ||
            e.message.contains('not_adult')) {
          _error =
              'Adult verification failed. Only an adult parent or guardian (18+) may supervise this account. Please retake the photo in good lighting.';
        } else if (e.message.contains('live_camera_photo_required')) {
          _error = 'Live camera photo required. Please take a clear selfie.';
        } else {
          _error = e.message;
        }
      });
    } catch (_) {
      setState(() {
        _error =
            'Verification failed due to a network or server issue. Please retry.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Adult Face Verification'),
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
                    _stepCircle('2', isDone: true, label: 'Email OTP'),
                    _stepLine(isDone: true),
                    _stepCircle('3', isActive: true, label: 'Face ID'),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                // Main Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Verify Adult Parent',
                          style: AppTypography.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const Text(
                          'LittleNet requires adult face verification to ensure only genuine parents or guardians manage kids accounts.',
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

                        // Status Info Banner
                        if (_statusMessage != null && _error == null) ...[
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.info.withValues(alpha: 0.1),
                              borderRadius: AppRadius.roundedSm,
                              border: Border.all(
                                  color: AppColors.info.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline,
                                    color: AppColors.info, size: 20),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    _statusMessage!,
                                    style: AppTypography.bodyMedium
                                        .copyWith(color: AppColors.info),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],

                        // Camera Viewport / Preview
                        Center(
                          child: Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _capturedPhotoBytes != null
                                    ? AppColors.success
                                    : AppColors.primary,
                                width: 3,
                              ),
                            ),
                            child: ClipOval(
                              child: _capturedPhotoBytes != null
                                  ? Image.memory(
                                      _capturedPhotoBytes!,
                                      fit: BoxFit.cover,
                                    )
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.camera_alt_outlined,
                                          size: 48,
                                          color: AppColors.primary
                                              .withValues(alpha: 0.6),
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                        const Text(
                                          'Look directly at camera',
                                          style: AppTypography.caption,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Action Buttons
                        if (_capturedPhotoBytes == null) ...[
                          AppButton(
                            text: 'Open Camera & Take Selfie',
                            icon: Icons.camera_alt,
                            isLoading: _isCapturing,
                            onPressed: _takeSelfie,
                          ),
                        ] else ...[
                          AppButton(
                            text: 'Verify & Activate Account',
                            icon: Icons.check_circle_outline,
                            isLoading: _isVerifying,
                            onPressed: _handleVerifyLiveness,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          AppButton(
                            text: 'Retake Photo',
                            variant: ButtonVariant.secondary,
                            icon: Icons.refresh,
                            onPressed: _isVerifying ? null : _takeSelfie,
                          ),
                        ],
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
            color: isActive || isDone ? AppColors.primary : AppColors.textMuted,
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
