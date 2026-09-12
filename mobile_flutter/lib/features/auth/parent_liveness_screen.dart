import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import '../../api.dart';
import '../../brand_logo.dart';
import '../../core/auth/auth_state.dart';
import '../../core/biometrics/face_biometrics.dart';
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

class _ParentLivenessScreenState extends State<ParentLivenessScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();

  CameraController? _cameraController;
  bool _isCameraInitializing = true;
  bool _cameraAvailable = false;
  List<CameraDescription> _cameras = [];

  Uint8List? _capturedPhotoBytes;
  bool _isCapturing = false;
  bool _isVerifying = false;
  bool _blinkPassed = false;
  String? _error;
  String? _statusMessage;
  String _livenessPhase = 'CALIBRATING'; // CALIBRATING -> BLINK_NOW -> VERIFIED

  late FaceLivenessStateMachine _stateMachine;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );
  bool _isDetecting = false;
  double _currentLeftEye = 0.0;
  double _currentRightEye = 0.0;
  double _currentEulerY = 0.0;
  List<double>? _enrolledFeatureVector;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _stateMachine = FaceLivenessStateMachine(targetAction: FaceLivenessAction.blink);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initCamera();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _faceDetector.close();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    setState(() {
      _isCameraInitializing = true;
      _error = null;
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _isCameraInitializing = false;
          _cameraAvailable = false;
          _statusMessage = 'Camera not detected. Use system camera below.';
        });
        return;
      }

      final frontCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _cameraAvailable = true;
        _isCameraInitializing = false;
        _livenessPhase = 'CALIBRATING';
        _statusMessage =
            'Center your face in the oval. Keeping eyes open for calibration...';
      });

      _startMLKitLoop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
          _cameraAvailable = false;
          _statusMessage =
              'Live camera access unavailable. Tap "Open System Camera" to proceed.';
        });
      }
    }
  }

  void _startMLKitLoop() {
    Future.doWhile(() async {
      if (!mounted || _blinkPassed || _capturedPhotoBytes != null) return false;
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        await Future.delayed(const Duration(milliseconds: 150));
        return true;
      }

      if (_isDetecting) {
        await Future.delayed(const Duration(milliseconds: 60));
        return true;
      }

      _isDetecting = true;
      try {
        final photo = await _cameraController!.takePicture();
        final inputImage = InputImage.fromFilePath(photo.path);
        final faces = await _faceDetector.processImage(inputImage);

        if (mounted) {
          if (faces.isEmpty) {
            setState(() {
              _currentLeftEye = 0.0;
              _currentRightEye = 0.0;
              _currentEulerY = 0.0;
              _stateMachine.processObservation(const FaceObservation(
                faceCount: 0,
                leftEyeOpen: 0.0,
                rightEyeOpen: 0.0,
                headEulerY: 0.0,
                headEulerZ: 0.0,
                featureVector: [],
              ));
              _statusMessage = _stateMachine.statusMessage;
            });
          } else {
            final face = faces.first;
            final lEye = face.leftEyeOpenProbability ?? 0.0;
            final rEye = face.rightEyeOpenProbability ?? 0.0;
            final eulerY = face.headEulerAngleY ?? 0.0;
            final eulerZ = face.headEulerAngleZ ?? 0.0;
            final vec = LocalFaceBiometrics.extractFeatureVector(face);

            final obs = FaceObservation(
              faceCount: faces.length,
              leftEyeOpen: lEye,
              rightEyeOpen: rEye,
              headEulerY: eulerY,
              headEulerZ: eulerZ,
              featureVector: vec,
            );

            setState(() {
              _currentLeftEye = lEye;
              _currentRightEye = rEye;
              _currentEulerY = eulerY;
              _stateMachine.processObservation(obs);
              _statusMessage = _stateMachine.statusMessage;

              if (_stateMachine.state == LivenessState.actionPrompted ||
                  _stateMachine.state == LivenessState.actionTransitioned) {
                _livenessPhase = 'BLINK_NOW';
              } else if (_stateMachine.state == LivenessState.calibratingCenter) {
                _livenessPhase = 'CALIBRATING';
              }
            });

            if (_stateMachine.isCompleted) {
              final bytes = await File(photo.path).readAsBytes();
              HapticFeedback.heavyImpact();
              final neuralEmbedding = await LocalFaceBiometrics.extractNeuralEmbedding(bytes, face);
              setState(() {
                _capturedPhotoBytes = bytes;
                _enrolledFeatureVector = neuralEmbedding;
                _blinkPassed = true;
                _livenessPhase = 'VERIFIED';
                _statusMessage =
                    '✓ Eye blink test passed! Tap "Verify & Activate Account" below.';
              });
              return false;
            }
          }
        }

        try {
          File(photo.path).deleteSync();
        } catch (_) {}
      } catch (_) {
      } finally {
        _isDetecting = false;
      }

      await Future.delayed(const Duration(milliseconds: 120));
      return true;
    });
  }

  Future<void> _takeSelfieFallback() async {
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
          _blinkPassed = true;
          _livenessPhase = 'VERIFIED';
          _statusMessage =
              'Live photo captured. Tap "Verify & Activate Account" to complete.';
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

  void _resetCamera() {
    setState(() {
      _capturedPhotoBytes = null;
      _blinkPassed = false;
      _error = null;
      _livenessPhase = 'CALIBRATING';
    });
    _initCamera();
  }

  Future<void> _handleVerifyLiveness() async {
    if (_capturedPhotoBytes == null) {
      setState(() => _error = 'Please complete the live blink verification.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
      _statusMessage =
          'Analyzing adult face and activating parent account...';
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

        if (_enrolledFeatureVector != null) {
          await LocalFaceBiometrics.saveTemplate(user.userId, _enrolledFeatureVector!);
          if (res['biometric_key'] != null) {
            await LocalFaceBiometrics.saveBiometricKey(user.userId, res['biometric_key'].toString());
          }
        }

        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/parent/dashboard',
          (route) => false,
        );
        return;
      }
    } on ApiException catch (e) {
      setState(() {
        final low = e.message.toLowerCase();
        if (low.contains('under_age') || low.contains('adult_liveness_failed')) {
          _error =
              'Adult verification failed. Only an adult parent or guardian (18+) may supervise this account.';
        } else if (low.contains('live_camera_photo_required')) {
          _error =
              'Live camera photo required. Please center your face and blink.';
        } else if (low.contains('email_verification_required')) {
          _error = 'Email verification is required before activating account.';
        } else if (low.contains('pending_verification_expired')) {
          _error = 'Session expired. Please restart registration.';
        } else {
          _error =
              'Verification issue: ${e.message}. Please retake photo in good lighting.';
        }
      });
    } catch (_) {
      setState(() {
        _error =
            'Verification request failed. Please check your network connection and retry.';
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
                          'LittleNet requires a live eye blink test to ensure only genuine adult guardians manage kids accounts.',
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
                                color: AppColors.error.withValues(alpha: 0.3),
                              ),
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
                              color: _blinkPassed
                                  ? AppColors.success.withValues(alpha: 0.1)
                                  : AppColors.info.withValues(alpha: 0.1),
                              borderRadius: AppRadius.roundedSm,
                              border: Border.all(
                                color: _blinkPassed
                                    ? AppColors.success.withValues(alpha: 0.4)
                                    : AppColors.info.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _blinkPassed
                                      ? Icons.check_circle_outline
                                      : Icons.remove_red_eye_outlined,
                                  color: _blinkPassed
                                      ? AppColors.success
                                      : AppColors.info,
                                  size: 20,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    _statusMessage!,
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: _blinkPassed
                                          ? AppColors.success
                                          : AppColors.info,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],

                        // Live Camera / Viewport
                        Center(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              ScaleTransition(
                                scale: _capturedPhotoBytes == null &&
                                        _livenessPhase == 'BLINK_NOW'
                                    ? _pulseAnimation
                                    : const AlwaysStoppedAnimation(1.0),
                                child: Container(
                                  width: 240,
                                  height: 240,
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _blinkPassed
                                          ? AppColors.success
                                          : _livenessPhase == 'BLINK_NOW'
                                              ? AppColors.primaryLight
                                              : AppColors.primary,
                                      width: 3.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (_blinkPassed
                                                ? AppColors.success
                                                : AppColors.primary)
                                            .withValues(alpha: 0.25),
                                        blurRadius: 16,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: _buildCameraContent(),
                                  ),
                                ),
                              ),

                              // Live HUD Pill at Top of Viewport
                              Positioned(
                                top: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _blinkPassed
                                          ? AppColors.success
                                          : Colors.white24,
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    _blinkPassed
                                        ? 'BLINK VERIFIED ✓'
                                        : _livenessPhase == 'BLINK_NOW'
                                            ? 'BLINK NOW'
                                            : 'CALIBRATING EYES…',
                                    style: TextStyle(
                                      color: _blinkPassed
                                          ? AppColors.success
                                          : _livenessPhase == 'BLINK_NOW'
                                              ? Colors.amberAccent
                                              : Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Action Buttons
                        if (_capturedPhotoBytes == null) ...[
                          if (_cameraAvailable &&
                              _cameraController != null &&
                              _cameraController!.value.isInitialized) ...[
                            // Live ML Kit HUD stats bar
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade900,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Left: ${(_currentLeftEye * 100).toInt()}%',
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _currentLeftEye > 0.65 ? Colors.greenAccent : Colors.orangeAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Right: ${(_currentRightEye * 100).toInt()}%',
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _currentRightEye > 0.65 ? Colors.greenAccent : Colors.orangeAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Angle: ${_currentEulerY.toStringAsFixed(1)}°',
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: AppRadius.roundedSm,
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'AI Vision: Tracking natural eye blink...',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextButton.icon(
                              onPressed: _isCapturing ? null : _takeSelfieFallback,
                              icon: const Icon(Icons.camera_alt, size: 18),
                              label: const Text('Open System Camera (Fallback)'),
                            ),
                          ] else ...[
                            AppButton(
                              text: 'Open Camera & Take Selfie',
                              icon: Icons.camera_alt,
                              isLoading: _isCapturing,
                              onPressed: _takeSelfieFallback,
                            ),
                          ],
                        ] else ...[
                          AppButton(
                            text: 'Verify & Activate Account',
                            icon: Icons.check_circle_outline,
                            isLoading: _isVerifying,
                            onPressed: _handleVerifyLiveness,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          AppButton(
                            text: 'Retake Live Blink',
                            variant: ButtonVariant.secondary,
                            icon: Icons.refresh,
                            onPressed: _isVerifying ? null : _resetCamera,
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

  Widget _buildCameraContent() {
    if (_capturedPhotoBytes != null) {
      return Image.memory(
        _capturedPhotoBytes!,
        fit: BoxFit.cover,
        width: 240,
        height: 240,
      );
    }

    if (_isCameraInitializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5),
            SizedBox(height: 12),
            Text(
              'Starting camera…',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_cameraAvailable &&
        _cameraController != null &&
        _cameraController!.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _cameraController!.value.previewSize?.height ?? 240,
          height: _cameraController!.value.previewSize?.width ?? 240,
          child: CameraPreview(_cameraController!),
        ),
      );
    }

    // Camera not available fallback UI
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.camera_alt_outlined,
          size: 48,
          color: AppColors.primary.withValues(alpha: 0.6),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Camera access needed',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
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
